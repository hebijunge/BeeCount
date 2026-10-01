import 'package:intl/intl.dart';

/// 交易数据导出的文件命名：`账本1_账本2_开始_结束.ext`。
///
/// 开始/结束由调用方决定：用户选了时间段就用选的，没选的那一侧传这批账本
/// 最早/最晚一笔的时间。真的取不到交易（空账本）时才落到 [allPeriodLabel]。
String buildExportFileName({
  required List<String> ledgerNames,
  required String allPeriodLabel,
  required String fallbackLedgerName,
  DateTime? startDate,
  DateTime? endDate,
  required String extension,
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
  ];
  return '${parts.join('_')}.$extension';
}
