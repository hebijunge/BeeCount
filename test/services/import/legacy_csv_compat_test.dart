// 旧版导出文件的向后兼容。
//
// 原版 BeeCount 只能导出当前账本，产物是固定 12 列的 CSV（表头见
// lib/pages/data/export_page.dart 旧版），文件里**没有任何账本标识**。新包加了
// 多账本支持后，这份旧表头必须仍被原样识别：尤其是不能被新增的「账本」分支误
// 命中，否则老文件导入时会被当成带归属信息的文件，静默建出一个新账本，而不是
// 按旧行为写进当前账本。

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/import/parsers/generic_parser.dart';

void main() {
  final parser = GenericBillParser();

  // 与 HEAD 版本 app_zh.arb 的 exportCsvHeader* 逐字一致
  const legacyZhHeader = <String>[
    '类型', '分类', '二级分类', '金额', '币种', '账户', //
    '转出账户', '转入账户', '备注', '时间', '标签', '附件',
  ];
  const legacyEnHeader = <String>[
    'Type', 'Category', 'Subcategory', 'Amount', 'Currency', 'Account',
    'From Account', 'To Account', 'Note', 'Time', 'Tags', 'Attachments',
  ];

  const expectedMapping = <String, int>{
    'type': 0,
    'category': 1,
    'sub_category': 2,
    'amount': 3,
    'currency': 4,
    'account': 5,
    'from_account': 6,
    'to_account': 7,
    'note': 8,
    'date': 9,
    'tags': 10,
    'attachments': 11,
  };

  test('旧版中文表头：12 列映射不变，且不含账本列', () {
    final mapping = parser.mapColumns(legacyZhHeader);
    expect(mapping.containsKey('ledger'), isFalse,
        reason: '误命中会让旧文件导入时静默新建账本');
    expect(mapping, expectedMapping);
  });

  test('旧版英文表头：12 列映射不变，且不含账本列', () {
    final mapping = parser.mapColumns(legacyEnHeader);
    expect(mapping.containsKey('ledger'), isFalse,
        reason: '"Account"/"From Account" 不能被认成账本');
    expect(mapping, expectedMapping);
  });

  test('旧版数据行解析不出 ledger 字段', () {
    final mapping = parser.mapColumns(legacyZhHeader);
    final row = <String>[
      '支出', '餐饮', '午餐', '-38.50', 'CNY', '微信', //
      '', '', '地铁', '  2026-09-29 12:30:00  ', '日常', '',
    ];
    final parsed = parser.parseRow(row, mapping)!;
    expect(parsed.containsKey('ledger'), isFalse);
    expect(parsed['category'], '餐饮');
    expect(parsed['amount'], '-38.50');
  });

  test('新包的多账本 CSV 仍能识别第 0 列的账本列', () {
    final mapping = parser.mapColumns(['账本', ...legacyZhHeader]);
    expect(mapping['ledger'], 0);
    // 账本列占掉第 0 列后，其余字段整体右移一位
    expect(mapping['type'], 1);
    expect(mapping['sub_category'], 3);
    expect(mapping['to_account'], 8);
  });

  test('英文账本列同样可识别', () {
    expect(parser.mapColumns(['Ledger', ...legacyEnHeader])['ledger'], 0);
    expect(parser.mapColumns(['Ledger Name', ...legacyEnHeader])['ledger'], 0);
  });

  // 手工把旧文件合并成多账本文件时，「账本」列通常追加在末尾而不是第 0 列，
  // 列位置不能影响识别。
  test('账本列在末尾时同样可识别，且不影响其余列的索引', () {
    final mapping = parser.mapColumns([...legacyZhHeader, '账本']);
    expect(mapping['ledger'], 12);
    expect(mapping['type'], 0);
    expect(mapping['attachments'], 11);
  });
}
