import 'dart:typed_data';
import 'package:excel/excel.dart';

/// XLSX 文件读取工具
///
/// 将 Excel 文件转换为 CSV 格式字符串，便于后续使用现有的 CSV 解析逻辑
class XlsxReader {
  /// 读取 XLSX 文件字节并转换为 CSV 格式字符串
  ///
  /// 参数:
  /// - [bytes]: XLSX 文件的字节数据
  /// - [ledgerColumnHeader]: 注入的「账本」列表头文案（由调用方传 l10n 词）。
  ///   多账本导出是每账本一张 sheet，合并成一份 CSV 后必须靠这一列记住每行的来源
  ///   sheet，否则下游会把所有交易灌进用户当前所在的那一个账本。做成必填参数，
  ///   是为了让任何新增调用点都没办法悄悄退回"丢掉账本归属"的旧行为。
  /// - [summaryHeaderMarkers]: 汇总 sheet 的表头特征词（如「笔数」「结余」）。多账本
  ///   导出的第一张 sheet 是逐本统计而非账单，必须整表跳过，同必填的理由。
  ///
  /// 返回:
  /// - CSV 格式的字符串，每行用 \n 分隔，字段用逗号分隔，第 0 列是账本名
  static String convertXlsxToCSV(
    Uint8List bytes, {
    required String ledgerColumnHeader,
    required List<String> summaryHeaderMarkers,
  }) {
    try {
      // 解码 Excel 文件
      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        throw Exception('Excel 文件为空或无法读取');
      }

      final headerCell = _csvEscape(ledgerColumnHeader);
      final csvLines = <String>[];
      List<String>? header;

      // 导出功能会把多个账本写成多张 sheet（表头一致），所以这里遍历全部工作表；
      // 只取第一张的话，自己导出的多账本文件回导时会丢掉除第一个之外的所有账本。
      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName];
        if (sheet == null || sheet.rows.isEmpty) continue;

        final rows = <List<String>>[];
        for (final row in sheet.rows) {
          final fields = row.map((cell) {
            // 获取单元格值
            final value = cell?.value;

            if (value == null) {
              return '';
            }

            // 转换为字符串
            String text;
            if (value is SharedString) {
              text = value.toString();
            } else if (value is TextCellValue) {
              text = value.value.toString();
            } else if (value is IntCellValue) {
              text = value.value.toString();
            } else if (value is DoubleCellValue) {
              text = value.value.toString();
            } else if (value is BoolCellValue) {
              text = value.value.toString();
            } else if (value is DateCellValue) {
              // 日期格式化为 YYYY-MM-DD
              final date = value.asDateTimeLocal();
              text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            } else if (value is TimeCellValue) {
              // TimeCellValue 直接转字符串
              text = value.toString();
            } else if (value is DateTimeCellValue) {
              final dt = value.asDateTimeLocal();
              text =
                  '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
            } else {
              text = value.toString();
            }

            return _csvEscape(text);
          }).toList();

          // 整行皆空（Excel 尾部的空行）丢掉，免得导入时多出空记录。
          if (fields.any((field) => field.isNotEmpty)) rows.add(fields);
        }
        if (rows.isEmpty) continue;

        // 汇总 sheet 整表跳过：它若排在最前，会当上后面比对的参考表头，每张真账本
        // 都因表头对不上被丢掉（数据全丢还不报错），而它自己的行会被当成交易灌进
        // 一个叫「汇总」的账本。
        if (_isSummaryHeader(rows.first, summaryHeaderMarkers)) continue;

        // 第 0 列贴上来源 sheet 名；表头行贴列名。sheet 名同样要过 CSV 转义，
        // 否则带逗号的账本名会把整行的列数撑乱。
        final stamped = <List<String>>[
          [headerCell, ...rows.first],
          for (final dataRow in rows.skip(1)) [_csvEscape(sheetName), ...dataRow],
        ];

        if (header == null) {
          header = stamped.first;
          csvLines.addAll(stamped.map((fields) => fields.join(',')));
          continue;
        }

        // 表头对不上，说明这张表不是同一份账单数据（比如用户自己的说明页），整表跳过。
        if (!_sameHeader(header, stamped.first)) continue;
        csvLines.addAll(stamped.skip(1).map((fields) => fields.join(',')));
      }

      if (csvLines.isEmpty) {
        throw Exception('工作表为空');
      }

      return csvLines.join('\n');
    } catch (e) {
      throw Exception('解析 Excel 文件失败: $e');
    }
  }

  /// CSV 转义：含逗号、双引号、换行符的字段要用双引号包裹，内部双引号翻倍。
  static String _csvEscape(String text) {
    if (text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  /// 表头里每个 [markers] 都能在某一列上匹配到，就认定这是汇总页。
  ///
  /// 用「包含」而不是「整行相等」：金额列表头带着币种后缀（收入(CNY)），用户也可能
  /// 在 Excel 里自己动过列。
  static bool _isSummaryHeader(List<String> headerRow, List<String> markers) {
    if (markers.isEmpty) return false;
    final cells = headerRow.map((cell) => cell.trim()).toList();
    return markers.every((marker) => cells.any((cell) => cell.contains(marker)));
  }

  static bool _sameHeader(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].trim() != right[i].trim()) return false;
    }
    return true;
  }
}
