import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/core/bill_info.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/bill_creation_service.dart';
import '../../services/data/tag_seed_service.dart';
import '../../styles/tokens.dart';
import '../../utils/format_utils.dart';
import '../biz/category_selector_dialog.dart';
import '../biz/ledger_selector_dialog.dart';

/// 剪贴板记账的**入账前**预览弹窗。
///
/// 现有 AI 记账链路是「提取完直接落库、再给卡片撤销」；剪贴板这条是被动触发，
/// 用户没有主动表达记账意图，所以必须先看后确认。每笔可改金额 / 类型 / 分类 /
/// 备注 / 账本，其余字段（时间 / 账户 / 币种 / 标签）沿用模型提取值。
///
/// 返回成功入账的笔数；`null` = 用户取消。
class ClipboardBillPreviewDialog extends ConsumerStatefulWidget {
  const ClipboardBillPreviewDialog({
    super.key,
    required this.bills,
    required this.sourceText,
    required this.defaultLedgerId,
  });

  final List<BillInfo> bills;

  /// 剪贴板原文，弹窗顶部展示给用户核对。
  final String sourceText;
  final int defaultLedgerId;

  static Future<int?> show(
    BuildContext context, {
    required List<BillInfo> bills,
    required String sourceText,
    required int defaultLedgerId,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => ClipboardBillPreviewDialog(
        bills: bills,
        sourceText: sourceText,
        defaultLedgerId: defaultLedgerId,
      ),
    );
  }

  @override
  ConsumerState<ClipboardBillPreviewDialog> createState() =>
      _ClipboardBillPreviewDialogState();
}

/// 一行可编辑账单。可编辑字段摊在这里而不是走 `BillInfo.copyWith`，是因为
/// `copyWith` 用 `x ?? this.x` 合并、传 null 表示"不改"，清不掉分类。
class _EditableBill {
  _EditableBill({
    required this.source,
    required this.type,
    required String amountText,
    required String note,
    required this.categoryName,
    required this.ledgerId,
  })  : amountController = TextEditingController(text: amountText),
        noteController = TextEditingController(text: note);

  /// 模型提取的原始账单，提供不可编辑字段（时间 / 账户 / 币种 / 标签）。
  final BillInfo source;

  final TextEditingController amountController;
  final TextEditingController noteController;

  BillType type;
  String? categoryName;
  int ledgerId;

  double? get magnitude => double.tryParse(amountController.text.trim());

  bool get hasValidAmount => (magnitude ?? 0) > 0;

  /// 仅在 [hasValidAmount] 为 true 时调用。
  BillInfo toBill() {
    final magnitude = this.magnitude!;
    final note = noteController.text.trim();
    return BillInfo(
      // 约定：支出为负、收入与转账为正（见 [BillInfo.amount]）。
      amount: type == BillType.expense ? -magnitude : magnitude,
      time: source.time,
      note: note.isEmpty ? null : note,
      category: categoryName,
      type: type,
      account: source.account,
      fromAccount: source.fromAccount,
      toAccount: source.toAccount,
      tags: source.tags,
      currency: source.currency,
      ledgerId: ledgerId,
      confidence: source.confidence,
    );
  }

  void dispose() {
    amountController.dispose();
    noteController.dispose();
  }
}

class _ClipboardBillPreviewDialogState
    extends ConsumerState<ClipboardBillPreviewDialog> {
  late final List<_EditableBill> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final bill in widget.bills)
        _EditableBill(
          source: bill,
          type: bill.type ?? BillType.expense,
          amountText: (bill.amount?.abs() ?? 0).toStringAsFixed(2),
          note: bill.note ?? '',
          categoryName: bill.category,
          ledgerId: bill.ledgerId ?? widget.defaultLedgerId,
        ),
    ];
    // 金额是 controller 内部状态，不挂监听的话改数字不会重建，
    // 「金额不合法」提示和「入账 N 笔」计数都会停在初始值。
    for (final item in _items) {
      item.amountController.addListener(_onAmountEdited);
    }
  }

  void _onAmountEdited() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final item in _items) {
      _detach(item);
    }
    super.dispose();
  }

  void _detach(_EditableBill item) {
    item.amountController.removeListener(_onAmountEdited);
    item.dispose();
  }

  int get _validCount => _items.where((item) => item.hasValidAmount).length;

  /// 分类列表按收/支分别维护，换类型后原分类多半不成立，所以清空让用户重选，
  /// 而不是留着一个会被落库兜底成「其他」的假象。
  void _setType(_EditableBill item, BillType type) {
    setState(() {
      item.type = type;
      item.categoryName = null;
    });
  }

  Future<void> _pickCategory(_EditableBill item) async {
    final type = switch (item.type) {
      BillType.income => 'income',
      BillType.expense => 'expense',
      BillType.transfer => 'transfer',
    };
    final category = await showCategorySelector(
      context,
      type: type,
      ledgerId: item.ledgerId,
    );
    if (category == null || !mounted) return;
    setState(() => item.categoryName = category.name);
  }

  Future<void> _pickLedger(_EditableBill item) async {
    final ledgerId =
        await showLedgerSelector(context, currentLedgerId: item.ledgerId);
    if (ledgerId == null || !mounted) return;
    setState(() => item.ledgerId = ledgerId);
  }

  void _remove(_EditableBill item) {
    setState(() {
      _items.remove(item);
      _detach(item);
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final persister = BillCreationService(ref.read(repositoryProvider));
    setState(() => _saving = true);

    var saved = 0;
    for (final item in _items) {
      if (!item.hasValidAmount) continue;
      final txId = await persister.createFromBill(
        bill: item.toBill(),
        ledgerId: item.ledgerId,
        billingTypes: const [TagSeedService.billingTypeAi],
        l10n: l10n,
      );
      if (txId != null) saved++;
    }

    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;

    return AlertDialog(
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.clipboardBillDialogTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context)),
            ),
            const SizedBox(height: 8),
            _SourcePreview(text: widget.sourceText),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _BillEditor(
                        item: _items[i],
                        canRemove: _items.length > 1,
                        onTypeChanged: (type) => _setType(_items[i], type),
                        onCategoryTapped: () => _pickCategory(_items[i]),
                        onLedgerTapped: () => _pickLedger(_items[i]),
                        onRemove: () => _remove(_items[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_saving || _validCount == 0) ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.clipboardBillConfirm(_validCount)),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SourcePreview extends StatelessWidget {
  const _SourcePreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceInput(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: BeeTokens.textSecondary(context)),
      ),
    );
  }
}

/// 单笔账单的编辑卡片。
class _BillEditor extends ConsumerWidget {
  const _BillEditor({
    required this.item,
    required this.canRemove,
    required this.onTypeChanged,
    required this.onCategoryTapped,
    required this.onLedgerTapped,
    required this.onRemove,
  });

  final _EditableBill item;
  final bool canRemove;
  final ValueChanged<BillType> onTypeChanged;
  final VoidCallback onCategoryTapped;
  final VoidCallback onLedgerTapped;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ledger =
        ref.watch(ledgerByIdProvider(item.ledgerId)).asData?.value;
    final currency = ledger?.currency;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: BeeTokens.divider(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canRemove)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_outlined, size: 18),
                tooltip: l10n.commonDelete,
              ),
            ),
          TextField(
            controller: item.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: l10n.clipboardBillAmountLabel,
              suffixText: (currency != null && currency.isNotEmpty)
                  ? currency.toUpperCase()
                  : null,
              errorText:
                  item.hasValidAmount ? null : l10n.clipboardBillAmountInvalid,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: item.noteController,
            decoration: InputDecoration(
              isDense: true,
              labelText: l10n.clipboardBillNoteLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          _TypeRow(
            label: l10n.clipboardBillTypeLabel,
            value: item.type,
            onChanged: onTypeChanged,
          ),
          _PickerRow(
            label: l10n.clipboardBillCategoryLabel,
            value: item.categoryName ?? l10n.commonUncategorized,
            onTap: onCategoryTapped,
          ),
          _PickerRow(
            label: l10n.clipboardBillLedgerLabel,
            value: ledger == null
                ? '#${item.ledgerId}'
                : translateLedgerName(context, ledger.name),
            onTap: onLedgerTapped,
          ),
        ],
      ),
    );
  }
}

/// 收/支/转账下拉。放在分类上一行：换类型会清空分类，顺序上也该先定类型再选分类。
class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final BillType value;
  final ValueChanged<BillType> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    String text(BillType type) {
      switch (type) {
        case BillType.income:
          return l10n.clipboardBillTypeIncome;
        case BillType.expense:
          return l10n.clipboardBillTypeExpense;
        case BillType.transfer:
          return l10n.clipboardBillTypeTransfer;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BeeTokens.textSecondary(context)),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BillType>(
                value: value,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: BeeTokens.surfaceElevated(context),
                items: [
                  for (final type in BillType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(
                        text(type),
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: BeeTokens.textPrimary(context)),
                      ),
                    ),
                ],
                onChanged: (next) {
                  if (next != null && next != value) onChanged(next);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BeeTokens.textSecondary(context)),
              ),
            ),
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: BeeTokens.textPrimary(context)),
              ),
            ),
            Icon(Icons.keyboard_arrow_right,
                size: 20, color: BeeTokens.textSecondary(context)),
          ],
        ),
      ),
    );
  }
}
