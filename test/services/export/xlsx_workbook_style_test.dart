// 导出 xlsx 的**样式与单元格类型**。
//
// 美化最容易踩的坑是"好看但读不回来"：金额从文本改成数字后，回导侧、以及依赖
// 文本比对的汇总 sheet 跳过逻辑都必须照常工作。这里锁四件事：金额格是真数值、
// 表头有蜂蜜黄底加粗、合计行加粗、每列都设了列宽。


import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:beecount/services/export/xlsx_workbook_writer.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LedgerExportSheet txSheet() => LedgerExportSheet(
        ledgerId: 1,
        ledgerName: '国宇',
        rows: const [
          ['账本', '时间', '金额'],
          ['国宇', '2026-09-30 09:11', '1000.00'],
          ['国宇', '2026-09-30 08:00', '80.00'],
        ],
        income: 1000,
        expense: 80,
        numericColumns: const {2},
      );

  LedgerExportSheet summarySheet() => LedgerExportSheet(
        ledgerId: summarySheetLedgerId,
        ledgerName: '汇总',
        rows: const [
          ['账本', '笔数', '支出(CNY)'],
          ['国宇', '2', '80.00'],
          ['合计', '2', '80.00'],
        ],
        numericColumns: const {1, 2},
      );

  /// 金额必须落成数值格：文本金额在 Excel 里左对齐、SUM 出来是 0。
  test('金额列写成数值并套两位小数格式', () async {
    final bytes = await buildWorkbookBytes([txSheet()]);
    final sheet = Excel.decodeBytes(bytes).tables['国宇']!;

    final amount = sheet.cell(CellIndex.indexByString('C2'));
    // 写的是 DoubleCellValue，但 excel 读回时按 XML 里的 '1000' 重新推断成 int ——
    // 关键是它落在数值族而不是文本，Excel 里才会右对齐并可求和。
    expect(amount.value, isNumericCell);
    expect(amount.cellStyle?.numberFormat.formatCode, '#,##0.00');

    // 时间、账本名保持文本，否则回导比对会错。
    expect(sheet.cell(CellIndex.indexByString('B2')).value, isA<TextCellValue>());
    expect(sheet.cell(CellIndex.indexByString('A2')).value, isA<TextCellValue>());
  });

  test('整数计数落 Int，金额带小数落 Double', () async {
    final bytes = await buildWorkbookBytes([summarySheet()]);
    final sheet = Excel.decodeBytes(bytes).tables['汇总']!;

    expect(sheet.cell(CellIndex.indexByString('B2')).value, isA<IntCellValue>());
    expect(sheet.cell(CellIndex.indexByString('C2')).value, isNumericCell);
    expect(sheet.cell(CellIndex.indexByString('C2')).cellStyle?.numberFormat.formatCode,
        '#,##0.00');
  });

  test('表头蜂蜜黄底加粗，合计行加粗', () async {
    final bytes = await buildWorkbookBytes([
      summarySheet(),
      txSheet(),
    ]);
    final sheet = Excel.decodeBytes(bytes).tables['汇总']!;

    final header = sheet.cell(CellIndex.indexByString('A1'));
    expect(header.cellStyle?.isBold, isTrue);
    expect(header.cellStyle?.backgroundColor.colorHex, 'FFFFC94A');

    expect(sheet.cell(CellIndex.indexByString('A3')).cellStyle?.isBold, isTrue,
        reason: '汇总 sheet 末行是合计行');
    expect(sheet.cell(CellIndex.indexByString('A2')).cellStyle?.isBold, isFalse,
        reason: '普通账本行不该跟着加粗');
  });

  test('每列都设了列宽，长中文列名不会挤成一格', () async {
    final bytes = await buildWorkbookBytes([txSheet()]);
    final sheet = Excel.decodeBytes(bytes).tables['国宇']!;

    final widths = sheet.getColumnWidths;
    expect(widths.keys, containsAll([0, 1, 2]));
    // 时间列 16 字符宽 + 边距；金额列短内容也吃保底宽。
    expect(widths[1], greaterThanOrEqualTo(18));
    expect(widths[2], greaterThanOrEqualTo(10));
  });

  test('样式化之后回导照旧：数字格读回文本，金额解析不破', () async {
    final bytes = await buildWorkbookBytes([txSheet()]);
    final sheet = Excel.decodeBytes(bytes).tables['国宇']!;
    final raw = sheet.cell(CellIndex.indexByString('C2')).value;
    final text = raw is TextCellValue ? raw.value.toString() : '$raw';
    expect(double.parse(text.replaceAll(RegExp(r'[^0-9.]'), '')), 1000.0);
    // 行序也保持：第 0 行仍是表头。
    expect(
      sheet.rows.first.map((c) => '${c!.value}'),
      ['账本', '时间', '金额'],
    );
  });
}

/// 数值格族：写回读时 excel 包可能在 Int/Double 之间重新推断，两者都算数。
final isNumericCell = predicate<Object>(
    (v) => v is IntCellValue || v is DoubleCellValue, '数值单元格');

