// 多账本汇总 sheet 的内容。
//
// 汇总页是给人核对账用的，数字必须跟各账本自己摊开的那些行同源：这里锁表头（金额列
// 带主币种码）、逐本的笔数/收入/支出/结余，以及结余=收入-支出。笔数取的是已摊开的
// 数据行数，所以它天然等于该账本导出的行数，不会另算一套对不上。

import 'package:beecount/l10n/app_localizations_zh.dart';
import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10n = AppLocalizationsZh();

LedgerExportSheet _ledger(
  int id,
  String name, {
  required int rows,
  required double income,
  required double expense,
}) =>
    LedgerExportSheet(
      ledgerId: id,
      ledgerName: name,
      // 第 0 行是表头，所以摊开的交易数 = rows + 1。
      rows: List.generate(rows + 1, (i) => const ['x']),
      income: income,
      expense: expense,
    );

void main() {
  test('汇总页逐本给出笔数与收支，结余等于收入减支出', () {
    final summary = TransactionExportService.buildSummarySheet(
      _l10n,
      [
        _ledger(1, '华恒远', rows: 1, income: 0, expense: 150),
        _ledger(2, '国宇', rows: 2, income: 1000, expense: 80),
      ],
      currencyCode: 'CNY',
    );

    expect(summary.ledgerId, summarySheetLedgerId);
    expect(summary.ledgerName, '汇总');
    expect(summary.rows.first, ['账本', '笔数', '收入(CNY)', '支出(CNY)', '结余(CNY)']);
    expect(summary.rows[1], ['华恒远', '1', '0.00', '150.00', '-150.00']);
    expect(summary.rows[2], ['国宇', '2', '1000.00', '80.00', '920.00']);
    expect(summary.rows.last, ['合计', '3', '1000.00', '230.00', '770.00'],
        reason: '末行是合计行：笔数/金额列求和，结余=总收入-总支出');
    expect(summary.dataRowCount, 3, reason: '两个账本行 + 合计行');
  });

  test('默认只勾「账本/笔数/支出」三列，拖动排序后立即生效', () {
    // 收入与结余默认收起（结余可自算），勾选集合决定列，顺序数组决定位置。
    final summary = TransactionExportService.buildSummarySheet(
      _l10n,
      [_ledger(1, '国宇', rows: 2, income: 1000, expense: 80)],
      currencyCode: 'CNY',
      summaryColumns: SummaryColumn.defaultSelected,
      summaryOrder: [
        SummaryColumn.expense,
        SummaryColumn.ledger,
        SummaryColumn.count,
      ],
    );

    expect(summary.rows.first, ['支出(CNY)', '账本', '笔数']);
    expect(summary.rows[1], ['80.00', '国宇', '2']);
  });

  test('取消勾选只留账本/笔数，金额合计跟着消失', () {
    final summary = TransactionExportService.buildSummarySheet(
      _l10n,
      [
        _ledger(1, '华恒远', rows: 1, income: 0, expense: 150),
        _ledger(2, '国宇', rows: 2, income: 1000, expense: 80),
      ],
      currencyCode: 'CNY',
      summaryColumns: {SummaryColumn.ledger, SummaryColumn.count},
    );

    expect(summary.rows.first, ['账本', '笔数']);
    expect(summary.rows.last, ['合计', '3']);
  });

  test('金额列表头始终带上折算所用的币种', () {
    // 汇总数字是 nativeAmount（主币种折算值），不标币种就会被当成原币相加。
    final summary = TransactionExportService.buildSummarySheet(
      _l10n,
      [_ledger(1, '日常', rows: 0, income: 0, expense: 0)],
      currencyCode: 'usd',
    );

    expect(summary.rows.first, ['账本', '笔数', '收入(USD)', '支出(USD)', '结余(USD)']);
  });

  test('单账本也造得出汇总页（是否启用由调用方按多账本判定）', () {
    final summary = TransactionExportService.buildSummarySheet(
      _l10n,
      [_ledger(7, '旅行', rows: 3, income: 50, expense: 120.5)],
      currencyCode: 'CNY',
    );

    expect(summary.rows, hasLength(3));
    expect(summary.rows[1], ['旅行', '3', '50.00', '120.50', '-70.50']);
    expect(summary.rows.last, ['合计', '3', '50.00', '120.50', '-70.50']);
  });
}
