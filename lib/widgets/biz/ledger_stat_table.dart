// 「我的」页各账本明细：账本 / 笔数 / 结余 三列表。
//
// 原先每行自带一遍「总笔数 / 账本结余」标签，三本账就重复六次；加上名字列定宽 96、
// 两个数字列平分剩余空间，上下行对不齐。这里列标题只画一次，数字列定宽右对齐，
// 长金额用 FittedBox 缩放而不是撑破列宽。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/statistics_providers.dart';
import '../../providers/theme_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import 'amount_text.dart';

/// 数字列必须定宽才能上下对齐，账本名吃掉剩余宽度。
const double _kCountColWidth = 40;
const double _kBalanceColWidth = 108;
const double _kColumnGap = 10;

/// 各账本逐本明细表。[currencyCode] 传主币种，结余已是该币种口径。
class LedgerStatTable extends ConsumerWidget {
  const LedgerStatTable({
    super.key,
    required this.ledgers,
    required this.currencyCode,
  });

  final List<PerLedgerStat> ledgers;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ledgers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LedgerTableHeader(),
        for (var i = 0; i < ledgers.length; i++) ...[
          _LedgerStatRow(
            name: ledgers[i].name,
            txCount: ledgers[i].txCount,
            balance: ledgers[i].balance,
            currencyCode: currencyCode,
          ),
          if (i != ledgers.length - 1)
            SizedBox(height: 10.0.scaled(context, ref)),
        ],
      ],
    );
  }
}

class _LedgerTableHeader extends ConsumerWidget {
  const _LedgerTableHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        // 这块在黄色头部背景上，textTertiary 淡得几乎看不见，跟顶部「总笔数 /
        // 账本结余」那两格取同一档。
        ?.copyWith(color: BeeTokens.textSecondary(context));
    return Padding(
      padding: EdgeInsets.only(bottom: 8.0.scaled(context, ref)),
      child: Row(
        children: [
          Expanded(child: Text(l10n.mineColLedger, style: style)),
          SizedBox(
            width: _kCountColWidth,
            child: Text(l10n.mineColCount,
                style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _kColumnGap),
          SizedBox(
            width: _kBalanceColWidth,
            child: Text(l10n.mineColBalance,
                style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _LedgerStatRow extends ConsumerWidget {
  const _LedgerStatRow({
    required this.name,
    required this.txCount,
    required this.balance,
    required this.currencyCode,
  });

  final String name;
  final int txCount;
  final double balance;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valueStyle = BeeTextTokens.strongTitle(context)
        .copyWith(fontSize: 16, color: BeeTokens.textPrimary(context));
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: BeeTokens.textPrimary(context)),
          ),
        ),
        SizedBox(
          width: _kCountColWidth,
          child: Text('$txCount',
              style: valueStyle, textAlign: TextAlign.right),
        ),
        const SizedBox(width: _kColumnGap),
        SizedBox(
          width: _kBalanceColWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: AmountText(
              value: balance,
              signed: false,
              showCurrency: true,
              useCompactFormat: ref.watch(compactAmountProvider),
              currencyCode: currencyCode,
              style: valueStyle.copyWith(
                color: balance >= 0
                    ? BeeTokens.textPrimary(context)
                    : BeeTokens.error(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
