// 首页 AI 悬浮球的四条行为：位置默认在右下角、点得动、长按拖得动、拖完记得住。
//
// 拖动方向最容易写反（屏幕 y 轴向下、而位置存的是"距底"），所以断言具体数值而不是
// "位置变了"；越界要夹回屏幕内，否则球会被拖出屏幕再也点不到。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/providers/ui_state_providers.dart';
import 'package:beecount/widgets/biz/ai_record_fab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const screen = Size(400, 800);
  const fabSize = Size.square(kAiFabSize);
  const bottomInset = 92.0;

  /// 球挂在 Scaffold 的 FAB 槽位上，和首页的实际挂法保持一致。
  Future<void> pumpFab(WidgetTester tester, {VoidCallback? onTap}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          floatingActionButton: AiRecordFab(
            tooltip: 'AI 助手',
            onTap: onTap ?? () {},
            bottomInset: bottomInset,
          ),
          floatingActionButtonLocation: AiRecordFabLocation(
            position: const Offset(16, 120),
            bottomInset: bottomInset,
          ),
          // 关掉位置过渡动画，球瞬移到新坐标，模拟首页的挂法。
          floatingActionButtonAnimator:
              FloatingActionButtonAnimator.noAnimation,
        ),
      ),
    ));
    await tester.pump();
  }

  Offset positionOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('ai-record-fab'))),
      ).read(aiFabPositionProvider);

  /// Scaffold 的 FAB 几何走 scaffoldSize 的浮点运算，分量和整值比会有 1e-9 级别的
  /// 尾差，所以拖动后断言分量 + 容差，整值相等只在无几何换算的初始态用。
  void expectPosition(WidgetTester tester, double right, double bottom) {
    final position = positionOf(tester);
    expect((position.dx - right).abs(), lessThan(1e-6));
    expect((position.dy - bottom).abs(), lessThan(1e-6));
  }

  group('坐标换算', () {
    test('「距右 / 距底」落到左上角坐标', () {
      final offset = aiFabOffsetFor(
        screen: screen,
        fab: fabSize,
        position: const Offset(16, 120),
        bottomInset: bottomInset,
      );
      // 400 - 16 - 52 = 332；800 - 92 - 120 - 52 = 536。
      expect(offset, const Offset(332, 536));
      expect(offset.dx + kAiFabSize, screen.width - 16);
      expect(offset.dy + kAiFabSize, screen.height - bottomInset - 120);
    });

    test('越界会被夹回可用区', () {
      final inside = aiFabClamped(
        const Offset(9999, 9999),
        screen: screen,
        fab: fabSize,
        bottomInset: bottomInset,
      );
      expect(inside.dx, screen.width - fabSize.width - kAiFabEdgeMargin);
      expect(inside.dy,
          screen.height - bottomInset - fabSize.height - kAiFabEdgeMargin);

      final below = aiFabClamped(
        const Offset(-500, -500),
        screen: screen,
        fab: fabSize,
        bottomInset: bottomInset,
      );
      expect(below, const Offset(kAiFabEdgeMargin, kAiFabEdgeMargin));
    });
  });

  testWidgets('默认停在右下角，且不会被底部导航栏压住', (tester) async {
    await pumpFab(tester);

    final rect = tester.getRect(find.byKey(const ValueKey('ai-record-fab')));
    // 距右 16、距底 120，球径 52。底栏顶边在 800-92=708，球整个停在它上方。
    expect(rect.right, screen.width - 16);
    expect(rect.bottom, screen.height - bottomInset - 120);
    expect(rect.bottom, lessThan(screen.height - bottomInset));
  });

  testWidgets('轻点跳 AI 记账，不挪位置', (tester) async {
    var tapped = 0;
    await pumpFab(tester, onTap: () => tapped++);

    await tester.tap(find.byKey(const ValueKey('ai-record-fab')));
    await tester.pump();

    expect(tapped, 1);
    expect(positionOf(tester), const Offset(16, 120));
  });

  testWidgets('长按往左上拖，距右和距底同时变大', (tester) async {
    await pumpFab(tester);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ai-record-fab'))));
    await tester.pump(const Duration(milliseconds: 600)); // 过长按阈值
    await gesture.moveBy(const Offset(-120, -200));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expectPosition(tester, 136, 320);
  });

  testWidgets('拖出屏幕会被夹回边缘，球不会丢', (tester) async {
    await pumpFab(tester);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ai-record-fab'))));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(900, 900)); // 往右下猛拖
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expectPosition(tester, kAiFabEdgeMargin, kAiFabEdgeMargin);
    expect(tester.takeException(), isNull);
  });

  group('位置持久化', () {
    test('重启后回到上次拖动的位置', () async {
      SharedPreferences.setMockInitialValues({
        'aiFabRight': 120.0,
        'aiFabBottom': 300.0,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(aiFabPositionInitProvider.future);

      expect(container.read(aiFabPositionProvider), const Offset(120, 300));
    });

    test('拖动后写回 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(aiFabPositionInitProvider.future);

      container.read(aiFabPositionProvider.notifier).state =
          const Offset(77, 88);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('aiFabRight'), 77);
      expect(prefs.getDouble('aiFabBottom'), 88);
    });
  });
}
