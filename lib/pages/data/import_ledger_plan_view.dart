import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data_import_service.dart';
import '../../styles/tokens.dart';

/// 一个账本归属分组：[ledgerName] 为 null 表示这些行没写账本（单账本文件、旧格式）。
typedef ImportLedgerGroup = ({String? ledgerName, int count});

/// 写策略值：并入已有账本（默认）/ 总是新建账本。
const String importStrategyOverwrite = 'overwrite';
const String importStrategyNew = 'new';

/// 未标注账本（兜底进当前账本）那组在勾选/策略 map 里用的 key。
const String currentLedgerGroupKey = '\u0000current';

/// 导入前说清「这些行会落到哪本账」：并进已有账本的、要新建账本的，各给一个明显标识。
///
/// 只数行不解析交易：这一屏会跟着 setState 反复重建，把整份账单再解析一遍，几千行的
/// 文件会直接卡住。
///
/// 匹配用 [DataImportService.findLedgerIn] —— 跟真正落库时同一份规则，否则徽标会跟
/// 结果不一致：用户看着「并入已有」点下去，事后发现多出一本新账本。
class ImportLedgerPlanView extends StatelessWidget {
  const ImportLedgerPlanView({
    super.key,
    required this.groups,
    required this.ledgers,
    required this.currentLedgerName,
    this.selectedGroup,
    this.onSelectedGroupChanged,
    this.strategyOf,
    this.onStrategyChanged,
  });

  final List<ImportLedgerGroup> groups;
  final List<Ledger> ledgers;
  final String currentLedgerName;

  /// 某组是否勾选导入；不传=默认全选。null 组用 [currentLedgerGroupKey] 做 key。
  final bool? Function(String? ledgerName)? selectedGroup;
  final void Function(String? ledgerName, bool selected)? onSelectedGroupChanged;

  /// 某组的写入策略（'overwrite'/'new'），不传=默认覆盖。
  final String? Function(String ledgerName)? strategyOf;
  final void Function(String ledgerName, String strategy)? onStrategyChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 只有「没写账本」这一组时没什么可预告的，别为它多占一屏。
    final named = groups.where((group) => group.ledgerName != null).toList();
    if (named.isEmpty) return const SizedBox.shrink();
    // 未标注的那一组排到最后：它是兜底去向，用户先关心被点名了的账本。
    final ordered = [
      ...named,
      for (final group in groups)
        if (group.ledgerName == null) group,
    ];

    var newCount = 0;
    final rows = <Widget>[];
    for (final group in ordered) {
      final name = group.ledgerName;
      final isNew = name != null &&
          DataImportService.findLedgerIn(ledgers, name) == null;
      if (isNew) newCount++;
      rows.add(_groupRow(context, l10n, group: group, isNew: isNew));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.importLedgerPlanTitle,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(
          l10n.importLedgerPlanSummary(ordered.length, newCount),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: BeeTokens.textTertiary(context)),
        ),
        const SizedBox(height: 8),
        ...rows,
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _groupRow(
    BuildContext context,
    AppLocalizations l10n, {
    required ImportLedgerGroup group,
    required bool isNew,
  }) {
    final name = group.ledgerName;
    final label = name ?? '$currentLedgerName（${l10n.importLedgerPlanCurrent}）';
    final groupKey = name ?? currentLedgerGroupKey;
    final isSelected =
        selectedGroup == null ? true : (selectedGroup!(name) ?? true);
    // 策略只对「真实账本名」组有效：未标注组永远进当前账本，没有覆盖/新建可分。
    final showStrategy = name != null && onStrategyChanged != null;
    final currentStrategy =
        showStrategy ? (strategyOf?.call(name!) ?? importStrategyOverwrite) : importStrategyOverwrite;
    return Padding(
      key: ValueKey('import-ledger-plan-row-${name ?? '_current_'}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('import-ledger-plan-select-$groupKey'),
                value: isSelected,
                onChanged: onSelectedGroupChanged != null
                    ? (v) => onSelectedGroupChanged!(name, v ?? false)
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.count}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: BeeTokens.textTertiary(context)),
              ),
              const SizedBox(width: 8),
              _Badge(
                text: name == null
                    ? l10n.importLedgerPlanCurrent
                    : isNew
                        ? l10n.importLedgerPlanNew
                        : l10n.importLedgerPlanMerge,
                kind: name == null ? 'current' : (isNew ? 'new' : 'merge'),
                background: name == null
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : isNew
                        ? Theme.of(context).colorScheme.tertiaryContainer
                        : Theme.of(context).colorScheme.secondaryContainer,
                foreground: name == null
                    ? BeeTokens.textSecondary(context)
                    : isNew
                        ? Theme.of(context).colorScheme.onTertiaryContainer
                        : Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ],
          ),
          // 策略单独一行：大字号下 SegmentedButton 的固有宽度会把第一行的账本名
          // 挤成 0 宽（真机实测），名字看不见就没法核对去向，宁可多占一行。
          if (showStrategy)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 2),
              child: Row(
                children: [
                  _Badge(
                    text: l10n.importStrategyLabel,
                    kind: 'strategy',
                    background:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    foreground: BeeTokens.textSecondary(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<String>(
                        key: ValueKey('import-ledger-plan-strategy-$groupKey'),
                        segments: [
                          ButtonSegment(
                            value: importStrategyOverwrite,
                            label: Text(l10n.importStrategyMerge),
                          ),
                          ButtonSegment(
                            value: importStrategyNew,
                            label: Text(l10n.importStrategyNew),
                          ),
                        ],
                        selected: {currentStrategy},
                        onSelectionChanged: (s) =>
                            onStrategyChanged!(name!, s.first),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.kind,
    required this.background,
    required this.foreground,
  });

  final String text;
  final String kind;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('import-ledger-plan-badge-$kind'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
