import 'package:beecount/services/export/export_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('两端日期都取到时就是 账本_开始_结束', () {
    expect(
      buildExportFileName(
        ledgerNames: ['国宇', '华恒远', '国图'],
        allPeriodLabel: '全部',
        fallbackLedgerName: '账本',
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 9, 30),
        extension: 'xlsx',
      ),
      '国宇_华恒远_国图_20260105_20260930.xlsx',
    );
  });

  test('取不到交易的那一侧才落到「全部」占位', () {
    expect(
      buildExportFileName(
        ledgerNames: ['张三'],
        allPeriodLabel: '全部',
        fallbackLedgerName: '账本',
        startDate: null,
        endDate: null,
        extension: 'csv',
      ),
      '张三_全部_全部.csv',
    );
  });

  test('账本名里的文件系统非法字符被替换为空格', () {
    expect(
      buildExportFileName(
        ledgerNames: ['甲/乙:丙*', '  丁  '],
        allPeriodLabel: 'All',
        fallbackLedgerName: 'Ledger',
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 9, 30),
        extension: 'xlsx',
      ),
      '甲 乙 丙_丁_20260105_20260930.xlsx',
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
      ),
      'Ledger_All_All.xlsx',
    );
  });
}
