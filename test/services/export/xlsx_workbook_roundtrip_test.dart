// 多账本 xlsx 的写入 / 读回闭环测试。
//
// 锁死两件事：多个账本要各占一张 sheet 且读回时合并成一份数据（表头不重复）；
// 账本名要安全化成合法 sheet 名（非法字符、31 字符上限、重名后缀）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:beecount/services/export/xlsx_workbook_writer.dart';
import 'package:beecount/utils/xlsx_reader.dart';

const _header = ['类型', '分类', '金额'];

LedgerExportSheet _sheet(int id, String name, List<List<String>> dataRows) =>
    LedgerExportSheet(
      ledgerId: id,
      ledgerName: name,
      rows: [_header, ...dataRows],
    );

void main() {
  test('多账本写成多 sheet，读回合并成一份并保留账本归属', () async {
    final bytes = await buildWorkbookBytes([
      _sheet(1, '日常', [
        ['支出', '餐饮', '12.00'],
        ['收入', '工资', '8000.00'],
      ]),
      _sheet(2, '生意', [
        ['支出', '进货', '99.90'],
      ]),
    ]);

    final lines = const LineSplitter()
        .convert(XlsxReader.convertXlsxToCSV(Uint8List.fromList(bytes),
            ledgerColumnHeader: '账本'));

    // 1 行表头 + 3 行数据；第二个账本的表头被合并掉。
    expect(lines, hasLength(4));
    expect(lines.first, '账本,类型,分类,金额');
    // 每行第 0 列是来源 sheet 名 —— 下游靠它把交易分回各自账本，
    // 丢了就会把所有交易灌进用户当前所在的那一个账本。
    expect(lines.where((line) => line.startsWith('日常,')), hasLength(2));
    expect(lines.where((line) => line.startsWith('生意,')), hasLength(1));
    expect(
      lines.where((line) => line.contains('8000.00') && line.contains('进货')),
      isEmpty,
      reason: '不同账本的行不能混在一起',
    );
  });

  test('sheet 名安全化：非法字符、31 字符上限、重名后缀', () async {
    final bytes = await buildWorkbookBytes([
      _sheet(1, 'A/B:C*D?E[F]G', [
        ['支出', 'x', '1.00']
      ]),
      _sheet(2, '很长的账本名称' * 8, [
        ['支出', 'y', '2.00']
      ]),
      _sheet(3, '同名', [
        ['支出', 'z', '3.00']
      ]),
      _sheet(4, '同名', [
        ['支出', 'w', '4.00']
      ]),
    ]);

    final names = Excel.decodeBytes(bytes).tables.keys.toList();
    expect(names, hasLength(4));
    expect(names[0], isNot(anyOf(contains('/'), contains(':'), contains('*'))));
    expect(names[1].length, lessThanOrEqualTo(31));
    expect(names[3], '同名(2)', reason: '重名账本要自动加后缀，否则 sheet 会互相覆盖');
    expect(names, isNot(contains('Sheet1')), reason: '默认空表应被删掉');
  });

  test('空 sheet 列表直接报错，不产出坏文件', () {
    expect(() => buildWorkbookBytes([]), throwsA(isA<ArgumentError>()));
  });
}
