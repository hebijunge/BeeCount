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
            ledgerColumnHeader: '账本', summaryHeaderMarkers: const []));

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

  test('汇总 sheet 排在第一张，回导时整表忽略', () async {
    const summary = LedgerExportSheet(
      ledgerId: summarySheetLedgerId,
      ledgerName: '汇总',
      rows: [
        ['账本', '笔数', '收入(CNY)', '支出(CNY)', '结余(CNY)'],
        ['华恒远', '1', '0.00', '150.00', '-150.00'],
        ['国宇', '2', '1000.00', '80.00', '920.00'],
      ],
    );
    final bytes = await buildWorkbookBytes([
      summary,
      _sheet(1, '华恒远', [
        ['支出', '结构胶', '150.00'],
      ]),
      _sheet(2, '国宇', [
        ['支出', '水泥', '80.00'],
        ['收入', '工程款', '1000.00'],
      ]),
    ]);

    expect(Excel.decodeBytes(bytes).tables.keys.first, '汇总',
        reason: '多账本导出的第一张 sheet 就是汇总页');

    final lines = const LineSplitter().convert(
      XlsxReader.convertXlsxToCSV(
        Uint8List.fromList(bytes),
        ledgerColumnHeader: '账本',
        summaryHeaderMarkers: const ['笔数', '结余'],
      ),
    );

    // 1 行表头 + 3 行真实交易。汇总页若没被跳过：它会当上参考表头，两张真账本全被
    // 丢掉（数据静默全丢），而它自己的数字行会被灌进一个叫「汇总」的假账本。
    expect(lines, hasLength(4));
    expect(lines.first, '账本,类型,分类,金额');
    expect(lines.where((line) => line.startsWith('汇总,')), isEmpty);
    expect(lines.where((line) => line.startsWith('华恒远,')), hasLength(1));
    expect(lines.where((line) => line.startsWith('国宇,')), hasLength(2));
    expect(
      lines.where((line) => line.contains('1000.00')),
      hasLength(1),
      reason: '汇总页里的 1000.00 不该被当成一笔交易读回来',
    );
  });

  test('汇总列勾到不含「结余」时，靠 sheet 名照样跳过汇总页', () async {
    // 汇总列可勾选后默认只出「账本/笔数/支出」，表头特征词（笔数+结余）不再必然命中。
    // 真机就是这样让汇总页逃过跳过、抢当参考表头，把两张真账本整表丢掉。
    const summary = LedgerExportSheet(
      ledgerId: summarySheetLedgerId,
      ledgerName: '汇总',
      rows: [
        ['账本', '笔数', '支出(CNY)'],
        ['默认账本', '1', '35.00'],
        ['合计', '2', '185.00'],
      ],
    );
    final bytes = await buildWorkbookBytes([
      summary,
      _sheet(1, '默认账本', [
        ['2026-09-30 09:11', '35.00', ''],
      ]),
    ]);

    final lines = const LineSplitter().convert(
      XlsxReader.convertXlsxToCSV(
        Uint8List.fromList(bytes),
        ledgerColumnHeader: '账本',
        summaryHeaderMarkers: const ['笔数', '结余'],
        summarySheetNames: const ['汇总'],
      ),
    );

    expect(lines, hasLength(2), reason: '表头 + 唯一一笔真交易');
    expect(lines.last, startsWith('默认账本,'));
    expect(lines.where((line) => line.contains('合计')), isEmpty);
  });
}
