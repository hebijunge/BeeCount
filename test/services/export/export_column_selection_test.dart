// 导出列自定义的行为锁定。
//
// 勾选列这件事最容易出的两种事故：一是取消勾选后表头和数据行错位（少一列而另一列
// 还在），二是调用方漏勾金额导出一份没有金额的账单。前者靠输出顺序统一从枚举派生，
// 后者靠服务层强制补齐 —— 这里把两条都钉住。

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:beecount/services/import/parsers/generic_parser.dart';

void main() {
  group('列勾选解析', () {
    test('默认只勾「时间 / 备注 / 金额」', () {
      expect(
        ExportColumn.defaultSelected.resolved,
        [ExportColumn.amount, ExportColumn.note, ExportColumn.time],
      );
    });

    test('输出顺序按枚举声明顺序，不随点击次序变化', () {
      expect(
        {ExportColumn.time, ExportColumn.type, ExportColumn.amount}.resolved,
        [ExportColumn.type, ExportColumn.amount, ExportColumn.time],
      );
      // 同一组勾选换一种加法顺序，结果必须一致，否则两次导出的文件列序会漂。
      expect(
        {ExportColumn.amount, ExportColumn.time, ExportColumn.type}.resolved,
        {ExportColumn.time, ExportColumn.type, ExportColumn.amount}.resolved,
      );
    });

    test('金额是必选列，漏勾也会被补', () {
      expect({ExportColumn.note, ExportColumn.time}.resolved,
          contains(ExportColumn.amount));
      expect(<ExportColumn>{}.resolved, [ExportColumn.amount],
          reason: '一个都不勾时也不能产出没有金额的文件');
    });

    test('除金额外都可以取消', () {
      for (final column in ExportColumn.values) {
        expect(column.isRequired, column == ExportColumn.amount,
            reason: '${column.name} 的必选性不符合预期');
      }
    });

    test('全选等于完整列序', () {
      expect(ExportColumn.values.toSet().resolved, ExportColumn.values);
    });
  });

  // 精简列导出会直接影响回导：只勾三列时文件里没有「类型」，导入侧要能认得出账本
  // 归属、并把缺类型的行按支出兜底，而不是整份文件废掉。
  group('默认三列文件的回导识别', () {
    test('账本/金额/备注/时间都能映射，类型列确实缺失', () {
      final mapping = GenericBillParser()
          .mapColumns(['账本', '金额', '备注', '时间', '', '']);
      expect(mapping['ledger'], 0);
      expect(mapping['amount'], 1);
      expect(mapping['note'], 2);
      expect(mapping['date'], 3);
      expect(mapping.containsKey('type'), isFalse,
          reason: '默认勾选不含类型，缺列时导入侧按支出兜底是已知行为');
    });
  });
}
