import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/export/transaction_export_service.dart';
import '../../services/export/xlsx_workbook_writer.dart';
import '../../widgets/ui/ui.dart';
import 'export_preview_page.dart';

/// 导出落盘格式。
enum ExportFormat { csv, excel }

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool exporting = false;
  double progress = 0;
  String? savedPath;

  ExportFormat _format = ExportFormat.excel;

  /// null 表示用户还没手动选过，此时按「当前账本」作默认勾选。
  Set<int>? _selectedLedgerIds;

  /// 导出列勾选，默认「时间 / 备注 / 金额」。金额必选在服务层兜底，UI 里也不给取消。
  Set<ExportColumn> _columns = ExportColumn.defaultSelected;

  /// 用户勾过的账本集合；没勾过则回落到当前账本，保持旧版「只导当前账本」的行为。
  Set<int> _effectiveSelection(List<Ledger> ledgers, int currentLedgerId) {
    if (_selectedLedgerIds != null) return _selectedLedgerIds!;
    if (ledgers.isEmpty) return const {};
    if (ledgers.any((l) => l.id == currentLedgerId)) return {currentLedgerId};
    return {ledgers.first.id};
  }

  /// 按账本表的顺序输出勾选的 id，保证 sheet 顺序稳定、不随点击次序变化。
  List<int> _orderedIds(List<Ledger> ledgers, Set<int> selected) =>
      ledgers.where((l) => selected.contains(l.id)).map((l) => l.id).toList();

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final currentLedgerId = ref.watch(currentLedgerIdProvider);
    final ledgers = ref.watch(ledgersStreamProvider).valueOrNull ?? const [];
    final l10n = AppLocalizations.of(context);
    final selected = _effectiveSelection(ledgers, currentLedgerId);
    final ordered = _orderedIds(ledgers, selected);

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(title: l10n.exportTitle, showBack: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Text(l10n.exportDescription),
                const SizedBox(height: 16),
                Text(l10n.exportFormatLabel,
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _FormatOption(
                  title: l10n.exportFormatExcel,
                  subtitle: l10n.exportFormatExcelHint,
                  selected: _format == ExportFormat.excel,
                  onTap: () => setState(() => _format = ExportFormat.excel),
                ),
                const SizedBox(height: 8),
                _FormatOption(
                  title: l10n.exportFormatCsv,
                  subtitle: l10n.exportFormatCsvHint,
                  selected: _format == ExportFormat.csv,
                  onTap: () => setState(() => _format = ExportFormat.csv),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(l10n.exportLedgersLabel,
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                    if (ledgers.length > 1)
                      TextButton(
                        onPressed: exporting
                            ? null
                            : () => setState(() {
                                  _selectedLedgerIds =
                                      ledgers.map((l) => l.id).toSet();
                                }),
                        child: Text(l10n.exportAllLedgers),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final ledger in ledgers)
                      FilterChip(
                        label: Text(ledger.name),
                        selected: selected.contains(ledger.id),
                        onSelected: exporting
                            ? null
                            : (on) => setState(() {
                                  final next = {...selected};
                                  if (on) {
                                    next.add(ledger.id);
                                  } else {
                                    next.remove(ledger.id);
                                  }
                                  _selectedLedgerIds = next;
                                }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(l10n.exportColumnsLabel,
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final column in ExportColumn.values)
                      FilterChip(
                        label: Text(column.headerText(l10n)),
                        selected: _columns.contains(column) || column.isRequired,
                        onSelected: exporting || column.isRequired
                            ? null
                            : (on) => setState(() {
                                  final next = {..._columns};
                                  if (on) {
                                    next.add(column);
                                  } else {
                                    next.remove(column);
                                  }
                                  _columns = next;
                                }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.exportColumnsHint,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: exporting || ordered.isEmpty
                      ? null
                      : () => _openPreview(repo, ordered),
                  icon: const Icon(Icons.save_alt_outlined),
                  label: Text(Platform.isIOS
                      ? l10n.exportButtonIOS
                      : l10n.exportButtonAndroid),
                ),
                if (ordered.isEmpty && ledgers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(l10n.exportNoLedgerSelected),
                  ),
                const SizedBox(height: 16),
                if (exporting)
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LinearProgressIndicator(
                            value: progress == 0 ? null : progress),
                      ),
                    ],
                  ),
                if (savedPath != null) ...[
                  const SizedBox(height: 12),
                  Text(l10n.exportSavedTo(savedPath!)),
                ],
              ],
            ),
          )
        ],
      ),
    );
  }

  /// 先弹预览，用户确认后才真正落盘。
  ///
  /// 预览展示的是完整真实数据，但落盘仍走 _export 重新取数 —— 预览只是给人看的同一
  /// 份算法产物，不直接拿来写文件。
  Future<void> _openPreview(BaseRepository repo, List<int> ledgerIds) async {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExportPreviewPage(
          repository: repo,
          ledgerIds: ledgerIds,
          asExcel: _format == ExportFormat.excel,
          columns: {..._columns},
        ),
      ),
    );
    if (confirmed != true) return;
    await _export(repo, ledgerIds);
  }

  Future<void> _export(BaseRepository repo, List<int> ledgerIds) async {
    try {
      setState(() {
        exporting = true;
        progress = 0;
        savedPath = null;
      });

      // context 只在 await 之前取用，先把 l10n 与取数服务装配好。
      final l10n = AppLocalizations.of(context);
      final service = TransactionExportService(
        repository: repo,
        l10n: l10n,
        context: context,
      );

      final directory = await _prepareDirectory();
      final shareAfter = Platform.isIOS;
      final asExcel = _format == ExportFormat.excel;

      // 多账本时 CSV 靠「账本」列区分，Excel 靠 sheet 区分，所以只有 CSV 需要加列。
      final multiLedger = ledgerIds.length > 1;
      final sheets = <LedgerExportSheet>[];
      for (var i = 0; i < ledgerIds.length; i++) {
        final sheet = await service.buildSheet(
          ledgerIds[i],
          includeLedgerColumn: multiLedger && !asExcel,
          padTimeCell: !asExcel,
          columns: _columns,
          onProgress: (ratio) {
            if (!mounted) return;
            setState(() => progress = (i + ratio) / ledgerIds.length);
          },
        );
        sheets.add(sheet);
      }
      if (!mounted) return;

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String path;
      if (asExcel) {
        final bytes = await buildWorkbookBytes(sheets);
        path = p.join(directory, 'beecount_$ts.xlsx');
        await File(path).writeAsBytes(bytes);
      } else {
        // 第一个账本提供表头，其余只追加数据行，避免一张表里出现多次表头。
        final rows = <List<String>>[];
        for (final sheet in sheets) {
          rows.addAll(rows.isEmpty
              ? sheet.rows
              : sheet.rows.skip(1));
        }
        final csvStr = const ListToCsvConverter(eol: '\n').convert(rows);
        path = p.join(directory, 'beecount_$ts.csv');
        // UTF-8 BOM 让 Excel 正确识别中文编码。
        final utf8Bom = String.fromCharCode(0xFEFF);
        await File(path)
            .writeAsString(utf8Bom + csvStr, encoding: Encoding.getByName('utf-8')!);
      }

      if (!mounted) return;
      setState(() {
        savedPath = path;
        exporting = false;
        progress = 1;
      });

      if (shareAfter) {
        await Share.shareXFiles([XFile(path)], text: l10n.exportShareText);
        if (!mounted) return;
        await AppDialog.info(context,
            title: l10n.exportSuccessTitle,
            message: l10n.exportSuccessMessageIOS(path));
      } else {
        await AppDialog.info(context,
            title: l10n.exportSuccessTitle,
            message: l10n.exportSuccessMessageAndroid(path));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => exporting = false);
      final l10nError = AppLocalizations.of(context);
      await AppDialog.error(context,
          title: l10nError.exportFailedTitle, message: e.toString());
    }
  }

  /// iOS 写文档目录后走分享面板；Android 直接落到公共 Download/BeeCount。
  Future<String> _prepareDirectory() async {
    if (Platform.isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      return docDir.path;
    }
    const downloadPath = '/storage/emulated/0/Download/BeeCount';
    final dir = Directory(downloadPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return downloadPath;
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
