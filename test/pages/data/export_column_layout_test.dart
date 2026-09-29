// 导出列方块的两条 UI 约束：紧凑换行、长按拖动换位。
//
// 用户明确不要「一列一行」的列表（ReorderableListView 只能一列一行，所以换成 Wrap +
// LongPressDraggable），同时列顺序还得能自己调。服务层的 resolvedIn 用例锁得住落盘
// 顺序，但锁不住「多个一行」和「拖动真的能换位」，这两条只能在 widget 层验。
// 顺带锁一条：方块外面套了拖动手势后，点按仍然能勾选/取消。

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/data/export_page.dart';
import 'package:beecount/providers/database_providers.dart';
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
          // 页面无需真实 drift 流；用一次性流，避免 drift 的 debounce Timer
          // 在 fake async 测试环境里一直挂着。
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

  /// 这页有持续调度的帧，pumpAndSettle 会一直等到超时，所以手动推几帧。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    // 列方块在页面中下部，默认 800x600 的测试视口里会被 ListView 裁掉，
    // 撑高一点保证 12 个方块全部参与布局。
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    // 不用 pumpAndSettle：这页有持续调度的帧，settle 会一直等到超时。显式推进
    // 几帧，等 ledgersStreamProvider 的流送达、方块布局完成即可。
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }

  final wrap = find.byKey(const ValueKey('export-columns-wrap'));

  Finder chip(String label) => find.descendant(
        of: wrap,
        matching: find.widgetWithText(FilterChip, label),
      );

  List<String> labels(WidgetTester tester) => tester
      .widgetList<FilterChip>(
          find.descendant(of: wrap, matching: find.byType(FilterChip)))
      .map((chip) => (chip.label as Text).data!)
      .toList();

  /// 长按起点方块 → 拖到目标方块上松手，模拟用户重排列顺序。
  Future<void> dragChip(WidgetTester tester,
      {required String from, required String to}) async {
    final gesture = await tester.startGesture(tester.getCenter(chip(from)));
    await tester.pump(const Duration(milliseconds: 300)); // 超过 200ms 长按阈值
    await gesture.moveTo(tester.getCenter(chip(to)));
    await tester.pump();
    await gesture.up();
    await settle(tester);
  }

  testWidgets('导出列方块紧凑换行，不是一列一行', (tester) async {
    await pumpPage(tester);

    expect(labels(tester), hasLength(12));
    // 一列一行会有 12 个不同的纵向位置；换行布局下必然少于 12。
    final rows = tester
        .widgetList<FilterChip>(
            find.descendant(of: wrap, matching: find.byType(FilterChip)))
        .map((chip) => tester.getTopLeft(find.byWidget(chip)).dy.round())
        .toSet();
    expect(rows.length, lessThan(12),
        reason: '列方块挤成一列一行就违背需求了');
  });

  testWidgets('默认顺序：时间仍在金额前', (tester) async {
    await pumpPage(tester);

    final order = labels(tester);
    expect(order.first, '类型');
    expect(order.indexOf('时间'), lessThan(order.indexOf('金额')));
  });

  testWidgets('长按把时间拖到类型上，时间排到第一列', (tester) async {
    await pumpPage(tester);

    await dragChip(tester, from: '时间', to: '类型');

    expect(labels(tester).take(3).toList(), ['时间', '类型', '分类']);
  });

  testWidgets('方块套了拖动手势后点按仍能勾选/取消', (tester) async {
    await pumpPage(tester);

    bool selected(String label) =>
        tester.widget<FilterChip>(chip(label)).selected;

    expect(selected('备注'), isTrue); // 默认勾选时间/备注/金额
    await tester.tap(chip('备注'));
    await settle(tester);
    expect(selected('备注'), isFalse);

    await tester.tap(chip('币种'));
    await settle(tester);
    expect(selected('币种'), isTrue);
    // 金额必选，不给取消。
    expect(selected('金额'), isTrue);
  });
}
