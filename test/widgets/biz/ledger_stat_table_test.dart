// 各账本明细表的排版约束。
//
// 这张表返工过一次：每行自带一遍「总笔数 / 账本结余」标签，三本账就重复六遍，
// 名字列还定宽 96、两个数字列平分剩余空间，上下行对不齐。服务层测不出「整齐」，
// 只能在 widget 层锁：列标题只出现一次、数字列上下右对齐、长金额不撑破列宽。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/statistics_providers.dart';
import 'package:beecount/widgets/biz/ledger_stat_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  PerLedgerStat stat(String name, int count, double balance) =>
      (ledgerId: name.hashCode, name: name, txCount: count, balance: balance);

  Future<void> pumpTable(WidgetTester tester, List<PerLedgerStat> rows) async {
    await tester.binding.setSurfaceSize(const Size(360, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: LedgerStatTable(ledgers: rows, currencyCode: 'CNY'),
        ),
      ),
    ));
    await tester.pump();
  }

  List<double> rightsOf(WidgetTester tester, Finder finder) => tester
      .widgetList<Widget>(finder)
      .map((w) => tester.getTopRight(find.byWidget(w)).dx)
      .toList();

  final table = find.byType(LedgerStatTable);

  testWidgets('列标题只出现一次，行内不再重复「总笔数 / 账本结余」', (tester) async {
    await pumpTable(tester, [
      stat('国宇', 44, -2818),
      stat('华恒远', 4, -899),
    ]);

    expect(find.text('账本'), findsOneWidget);
    expect(find.text('笔数'), findsOneWidget);
    expect(find.text('结余'), findsOneWidget);
    expect(find.text('总笔数'), findsNothing);
    expect(find.text('账本结余'), findsNothing);
  });

  testWidgets('笔数与结余上下右对齐，且对齐到各自的列标题', (tester) async {
    await pumpTable(tester, [
      stat('国宇', 44, -2818),
      stat('华恒远', 4, -899),
      stat('国图', 2, -63),
    ]);

    final headerCountRight = tester.getTopRight(find.text('笔数')).dx;
    final headerBalanceRight = tester.getTopRight(find.text('结余')).dx;

    // 结余列外面套了定宽容器，取容器右边界而不是被缩放后的文字右边界。
    final balanceRights = rightsOf(
      tester,
      find.descendant(of: table, matching: find.byType(FittedBox)),
    );
    expect(balanceRights, hasLength(3));
    for (final dx in balanceRights) {
      expect((dx - headerBalanceRight).abs(), lessThan(1.0),
          reason: '结余要贴齐表头那一列');
    }

    final countRights = rightsOf(
      tester,
      find.descendant(
        of: table,
        matching: find.widgetWithText(Text, '44'),
      ),
    ).followedBy(rightsOf(
      tester,
      find.descendant(
        of: table,
        matching: find.widgetWithText(Text, '4'),
      ),
    )).toList();
    for (final dx in countRights) {
      expect((dx - headerCountRight).abs(), lessThan(1.0),
          reason: '笔数要贴齐表头那一列');
    }
  });

  testWidgets('长金额缩在列宽内，不溢出也不撑破表格', (tester) async {
    await pumpTable(tester, [
      stat('国宇', 44, -12345678.90),
      stat('华恒远', 4, 88),
    ]);

    expect(tester.takeException(), isNull);
    final tableRight = tester.getTopRight(table).dx;
    for (final dx in rightsOf(
      tester,
      find.descendant(of: table, matching: find.byType(FittedBox)),
    )) {
      expect(dx, lessThanOrEqualTo(tableRight + 0.5));
    }
  });

  testWidgets('账本名过长只省略，不挤掉数字列', (tester) async {
    await pumpTable(tester, [
      stat('某某某某某某某某某某某某某某某某某某某某某某某某某', 44, -2818),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('笔数'), findsOneWidget);
  });

  testWidgets('没有账本时整张表不画，也不留下孤零零的表头', (tester) async {
    await pumpTable(tester, const []);

    expect(find.text('结余'), findsNothing);
    expect(find.text('笔数'), findsNothing);
  });
}
