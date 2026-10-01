import 'package:beecount/services/export/export_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 1, 13, 29, 2);

  test('全量导出（时间段未设）出「全部」占位段', () {
    expect(
      buildExportFileName(
        ledgerNames: ['张三', '李四'],
        allPeriodLabel: '全部',
        fallbackLedgerName: '账本',
        startDate: null,
        endDate: null,
        extension: 'xlsx',
        now: now,
      ),
      '张三_李四_全部_全部_20261001_132902.xlsx',
    );
  });

  test('带时间段的日期段为 yyyyMMdd', () {
    expect(
      buildExportFileName(
        ledgerNames: ['张三'],
        allPeriodLabel: '全部',
        fallbackLedgerName: '账本',
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 9, 30),
        extension: 'csv',
        now: now,
      ),
      '张三_20260105_20260930_20261001_132902.csv',
    );
  });

  test('账本名里的文件系统非法字符被替换为空格', () {
    expect(
      buildExportFileName(
        ledgerNames: ['甲/乙:丙*', '  丁  '],
        allPeriodLabel: 'All',
        fallbackLedgerName: 'Ledger',
        startDate: null,
        endDate: null,
        extension: 'xlsx',
        now: now,
      ),
      '甲 乙 丙_丁_All_All_20261001_132902.xlsx',
    );
  });

  test('清洗后为空的账本名回退到占位名', () {
    expect(
      buildExportFileName(
        ledgerNames: ['/?*'],
        allPeriodLabel: 'All',
        fallbackLedgerName: 'Ledger',
        startDate: null,
        endDate: null,
        extension: 'xlsx',
        now: now,
      ),
      'Ledger_All_All_20261001_132902.xlsx',
    );
  });
}
