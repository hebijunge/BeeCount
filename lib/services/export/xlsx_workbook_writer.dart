import 'dart:math' as math;

import 'package:excel/excel.dart';

import 'transaction_export_service.dart';

/// 表头底色：与 App 的蜂蜜黄同族，但压暗一档 —— 纯主题色在白纸上太刺眼，
/// 深棕字配它对比度也够。
final ExcelColor _headerFill = ExcelColor.fromHexString('FFFFC94A');
final ExcelColor _headerText = ExcelColor.fromHexString('FF4A3200');
final ExcelColor _headerRule = ExcelColor.fromHexString('FFB8860B');

/// 把多个账本的表格写进**同一个** xlsx，每个账本占一张 sheet。
///
/// [sheets] 顺序即 sheet 顺序。账本名会被安全化成合法的 sheet 名（见
/// [_uniqueSheetName]），重名的账本自动追加 `(2)`、`(3)` 后缀。
///
/// 样式在落盘这一层统一加：表头蜂蜜黄底加粗带下边线、数字列写真数值并套千分位
/// 格式、列宽按内容估算 —— 全文本的表格在 Excel 里左对齐、没法求和，观感也差。
Future<List<int>> buildWorkbookBytes(List<LedgerExportSheet> sheets) async {
  if (sheets.isEmpty) {
    throw ArgumentError('至少需要一个账本才能生成 xlsx');
  }
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final taken = <String>{};

  for (final sheet in sheets) {
    final name = _uniqueSheetName(sheet.ledgerName, sheet.ledgerId, taken);
    final target = excel[name];
    final isSummary = sheet.ledgerId == summarySheetLedgerId;

    for (var r = 0; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final isHeader = r == 0;
      final isTotalRow = isSummary && r == sheet.rows.length - 1;
      for (var c = 0; c < row.length; c++) {
        final raw = row[c];
        final number =
            !isHeader && sheet.numericColumns.contains(c) && raw.isNotEmpty
                ? double.tryParse(raw)
                : null;
        final isDecimal = number != null && raw.contains('.');
        target.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          number == null
              ? TextCellValue(raw)
              : isDecimal
                  ? DoubleCellValue(number)
                  : IntCellValue(number.round()),
          cellStyle: _styleFor(
            header: isHeader,
            total: isTotalRow,
            numeric: number != null,
            decimal: isDecimal,
          ),
        );
      }
    }

    final columnCount =
        sheet.rows.fold<int>(0, (max, row) => math.max(max, row.length));
    for (var c = 0; c < columnCount; c++) {
      target.setColumnWidth(c, _columnWidth(sheet.rows, c));
    }
    if (sheet.rows.isNotEmpty) target.setRowHeight(0, 26);
  }

  // Excel.createExcel() 自带一张空默认表；它没被用作任何账本时才删掉，
  // 否则工作簿里会多出一张空白 sheet。
  if (defaultSheet != null && !taken.contains(defaultSheet.toLowerCase())) {
    excel.delete(defaultSheet);
  }

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('xlsx 序列化失败');
  }
  return bytes;
}

CellStyle _styleFor({
  required bool header,
  required bool total,
  required bool numeric,
  required bool decimal,
}) {
  if (header) {
    return CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: _headerText,
      backgroundColorHex: _headerFill,
      verticalAlign: VerticalAlign.Center,
      bottomBorder: Border(
        borderStyle: BorderStyle.Medium,
        borderColorHex: _headerRule,
      ),
    );
  }
  return CellStyle(
    bold: total,
    numberFormat: !numeric
        ? NumFormat.standard_0
        : NumFormat.custom(formatCode: decimal ? '#,##0.00' : '#,##0'),
  );
}

/// 列宽 = 该列最宽内容的显示宽度 + 边距，夹在 10~56 之间。
///
/// 中文按 2 个字符宽估（Excel 的宽度单位是 '0' 的个数，一个汉字约等于两个）。
double _columnWidth(List<List<String>> rows, int column) {
  var widest = 0;
  for (final row in rows) {
    if (column >= row.length) continue;
    final width = _displayWidth(row[column]);
    if (width > widest) widest = width;
  }
  return (widest + 3).clamp(10.0, 56.0).toDouble();
}

int _displayWidth(String text) {
  var width = 0;
  for (final unit in text.runes) {
    width += unit > 0x1100 ? 2 : 1;
  }
  return width;
}

/// Excel 的 sheet 名限制：非空、≤31 字符、不含 `: \ / ? * [ ]`。
///
/// 导入侧按账本名匹配 sheet 名时必须复用这一套规则（见
/// `DataImportService.ensureLedgerByName`）：账本名经过这里会变成另一个字符串，
/// 拿原名去比对就会匹配失败、静默新建一个重复账本。
String safeSheetName(String raw, int ledgerId) {
  // 账本名为空时用 ASCII 兜底名，避免把某一种语言的文案写死在 service 里。
  var name = raw.trim().isEmpty ? 'Ledger$ledgerId' : raw.trim();
  name = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ');
  if (name.length > 31) name = name.substring(0, 31);
  name = name.trim();
  return name.isEmpty ? 'Ledger$ledgerId' : name;
}

/// 生成不与 [taken] 冲突的 sheet 名，并把结果登记进 [taken]。
///
/// Excel 认为 sheet 名大小写不敏感且必须唯一，所以比对用小写形式。
String _uniqueSheetName(String raw, int ledgerId, Set<String> taken) {
  final base = safeSheetName(raw, ledgerId);
  if (!taken.contains(base.toLowerCase())) {
    taken.add(base.toLowerCase());
    return base;
  }
  for (var n = 2;; n++) {
    final suffix = '($n)';
    final stem = base.length > 31 - suffix.length
        ? base.substring(0, 31 - suffix.length)
        : base;
    final candidate = '$stem$suffix';
    if (!taken.contains(candidate.toLowerCase())) {
      taken.add(candidate.toLowerCase());
      return candidate;
    }
  }
}
