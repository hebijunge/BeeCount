import 'package:excel/excel.dart';

import 'transaction_export_service.dart';

/// 把多个账本的表格写进**同一个** xlsx，每个账本占一张 sheet。
///
/// [sheets] 顺序即 sheet 顺序。账本名会被安全化成合法的 sheet 名（见
/// [_safeSheetName]），重名的账本自动追加 `(2)`、`(3)` 后缀。
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
    for (final row in sheet.rows) {
      target.appendRow(row.map((value) => TextCellValue(value)).toList());
    }
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
