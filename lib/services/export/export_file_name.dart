import 'package:intl/intl.dart';

/// 交易数据导出的文件命名：`账本1_账本2_开始_结束_年月日_时分秒.ext`。
///
/// 时间段未设的一侧输出 [allPeriodLabel]（如「全部」）而不是省略，
/// 保证位置语义稳定——看到倒数第二段是日期就知道那是哪一端。
String buildExportFileName({
  required List<String> ledgerNames,
  required String allPeriodLabel,
  required String fallbackLedgerName,
  DateTime? startDate,
  DateTime? endDate,
  required String extension,
  required DateTime now,
}) {
  String namePart(String name) {
    // 文件系统非法字符替换成空格，保持文件名跨平台可写。
    final sanitized =
        name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    return sanitized.isEmpty ? fallbackLedgerName : sanitized;
  }

  String dayPart(DateTime? date) =>
      date == null ? allPeriodLabel : DateFormat('yyyyMMdd').format(date);

  final parts = <String>[
    ledgerNames.map(namePart).join('_'),
    dayPart(startDate),
    dayPart(endDate),
    DateFormat('yyyyMMdd_HHmmss').format(now),
  ];
  return '${parts.join('_')}.$extension';
}
