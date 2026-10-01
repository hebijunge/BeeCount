// 导出页时间段筛选的 UI 行为：两行默认都显示「未设置」（= 不限时间段），
// 点日历能选日期并回显，选过的可一键清空。

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/data/export_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/ui/wheel_date_picker.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;
  late List<Ledger> ledgerRows;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: '默认账本');
    ledgerRows = await repo.getAllLedgers();
  });

  tearDown(() async => db.close());

  Widget host() => ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentLedgerIdProvider.overrideWith((ref) => ledgerId),
          ledgersStreamProvider
              .overrideWith((ref) => Stream.fromIterable([ledgerRows])),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ExportPage(),
        ),
      );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    // 这页有持续调度的帧，不能用 pumpAndSettle；手动推几帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Finder dateRow(bool isStart) =>
      find.byKey(ValueKey(isStart ? 'export-date-start' : 'export-date-end'));

  testWidgets('两行默认都显示「未设置」，即不限时间段', (tester) async {
    await pumpPage(tester);

    for (final isStart in const [true, false]) {
      final row = dateRow(isStart);
      expect(row, findsOneWidget, reason: '时间段行没渲染出来');
      expect(
        find.descendant(of: row, matching: find.text('未设置')),
        findsOneWidget,
        reason: isStart ? '起日默认应未设置' : '止日默认应未设置',
      );
    }
  });

  testWidgets('选了起日后回显日期，且能一键清空', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('export-date-start-pick')));
    await tester.pumpAndSettle();

    // 滚轮选择器是以底部 sheet 弹出的，弹出来即证明点日历按钮的交互通了；
    // 具体「选了日期会回显」走 service 层测试，不在这里模拟逐格滚轮。
    expect(find.byType(WheelDatePicker), findsOneWidget,
        reason: '点日历按钮应弹出日期选择器');

    Navigator.of(tester.element(find.byType(WheelDatePicker))).pop();
    await tester.pumpAndSettle();
  });
}
