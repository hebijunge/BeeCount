// 导入前的「账本归属」预览。
//
// 用户要的是一眼看清「哪些并进已有账本、哪些会新建一本」。这块最容易骗人的方式是
// 预览自己判断一套、落库时 ensureLedgerByName 另一套 —— 所以匹配统一走
// DataImportService.findLedgerIn，用例里专门有一条按 sheet 安全化名命中的，锁住这点。

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/data/import_ledger_plan_view.dart';
import 'package:beecount/services/data_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late List<Ledger> ledgers;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await repo.createLedger(name: '日常');
    await repo.createLedger(name: '国宇');
    ledgers = await repo.getAllLedgers();
  });

  tearDown(() async => db.close());

  Future<void> pump(
    WidgetTester tester, {
    required List<ImportLedgerGroup> groups,
    List<Ledger>? existing,
    void Function(String? name, bool selected)? onSelectedGroupChanged,
    void Function(String name, String strategy)? onStrategyChanged,
  }) async {
    await tester.binding.setSurfaceSize(const Size(411, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: ImportLedgerPlanView(
          groups: groups,
          ledgers: existing ?? ledgers,
          currentLedgerName: '日常',
          onSelectedGroupChanged: onSelectedGroupChanged,
          onStrategyChanged: onStrategyChanged,
        ),
      ),
    ));
    await tester.pump();
  }

  Finder badge(String kind) =>
      find.byKey(ValueKey('import-ledger-plan-badge-$kind'));

  Finder rowOf(String name) =>
      find.byKey(ValueKey('import-ledger-plan-row-$name'));

  testWidgets('已有的标并入、没有的标新建，摘要给出新建数', (tester) async {
    await pump(tester, groups: const [
      (ledgerName: '国宇', count: 12),
      (ledgerName: '华恒远', count: 3),
    ]);

    expect(find.text('并入已有账本'), findsOneWidget);
    expect(find.text('新建账本'), findsOneWidget);
    expect(find.text('共 2 个账本，其中 1 个要新建'), findsOneWidget);
    // 徽标得挂在正确的那一行上，标错比不标更糟。
    expect(
      find.descendant(of: rowOf('国宇'), matching: badge('merge')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rowOf('华恒远'), matching: badge('new')),
      findsOneWidget,
    );
  });

  testWidgets('sheet 安全化名也算已有账本，不会谎报成新建', (tester) async {
    // 账本原名带非法字符时，导出写进 sheet 名的是安全化后的样子；回导按同一规则命中，
    // 预览若自己判断就会谎称「新建账本」，用户以为会多出一本。
    final slashedId = await repo.createLedger(name: 'A/B');
    final rows = await repo.getAllLedgers();

    await pump(
      tester,
      existing: rows,
      groups: const [(ledgerName: 'A B', count: 5)],
    );

    expect(DataImportService.findLedgerIn(rows, 'A B'), slashedId);
    expect(find.text('并入已有账本'), findsOneWidget);
    expect(find.text('新建账本'), findsNothing);
  });

  testWidgets('没写账本的行走当前账本，并排在被点名的账本后面', (tester) async {
    await pump(tester, groups: const [
      (ledgerName: null, count: 4),
      (ledgerName: '国宇', count: 2),
    ]);

    expect(find.text('记入当前账本'), findsOneWidget);
    expect(find.text('国宇'), findsOneWidget);
    expect(
      tester.getTopLeft(rowOf('国宇')).dy,
      lessThan(tester.getTopLeft(rowOf('_current_')).dy),
      reason: '兜底去向排最后，用户先看被点名了的账本',
    );
    expect(find.text('共 2 个账本，其中 0 个要新建'), findsOneWidget);
  });

  testWidgets('单账本文件不显示这一块', (tester) async {
    await pump(tester, groups: const [(ledgerName: null, count: 40)]);

    expect(find.text('账本归属'), findsNothing);
    expect(badge('current'), findsNothing);
  });

  testWidgets('默认全勾；取消勾选回调对应组名', (tester) async {
    final calls = <Object?>[];
    await pump(
      tester,
      groups: const [
        (ledgerName: null, count: 4),
        (ledgerName: '国宇', count: 12),
      ],
      onSelectedGroupChanged: (name, v) => calls..add(name)..add(v),
    );

    final box = find.byKey(const ValueKey('import-ledger-plan-select-国宇'));
    expect(tester.widget<Checkbox>(box).value, true, reason: '默认全选');
    await tester.tap(box);
    await tester.pump();
    expect(calls, ['国宇', false]);
  });

  testWidgets('未标注那组也能勾掉，回调传 null 组名', (tester) async {
    final calls = <Object?>[];
    await pump(
      tester,
      groups: const [
        (ledgerName: null, count: 4),
        (ledgerName: '国宇', count: 12),
      ],
      onSelectedGroupChanged: (name, v) => calls..add(name)..add(v),
    );

    await tester.tap(
        find.byKey(const ValueKey('import-ledger-plan-select-\u0000current')));
    await tester.pump();
    expect(calls, [null, false]);
  });

  testWidgets('写入策略默认「并入已有」，点「新建账本」回调 new', (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      groups: const [(ledgerName: '国宇', count: 12)],
      onStrategyChanged: (name, v) => calls.add('$name=$v'),
    );

    final segment =
        find.byKey(const ValueKey('import-ledger-plan-strategy-国宇'));
    expect(segment, findsOneWidget);
    final labelFinder =
        find.descendant(of: rowOf('国宇'), matching: find.text('国宇'));
    expect(tester.getSize(labelFinder).width, greaterThan(20),
        reason: '策略控件再宽也不能把账本名挤没——名字看不见就没法核对去向');
    expect(
      tester.widget<SegmentedButton<String>>(segment).selected,
      {importStrategyOverwrite},
      reason: '默认覆盖，不动策略就跟旧行为一致',
    );
    await tester.tap(find.descendant(
        of: segment, matching: find.text('新建账本')));
    await tester.pump();
    expect(calls, ['国宇=new']);
  });

  testWidgets('当前账本组没有策略可选——它永远进当前账本', (tester) async {
    await pump(
      tester,
      groups: const [
        (ledgerName: null, count: 4),
        (ledgerName: '国宇', count: 12),
      ],
      onStrategyChanged: (_, __) {},
    );

    expect(
      find.descendant(
        of: rowOf('_current_'),
        matching:
            find.byKey(const ValueKey('import-ledger-plan-strategy-\u0000current')),
      ),
      findsNothing,
    );
    expect(find.text('记入当前账本'), findsOneWidget);
  });
}
