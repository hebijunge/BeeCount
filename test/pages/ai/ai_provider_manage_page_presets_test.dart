// 服务商管理页：内置预设要出现在列表里、限流说明看得见，而且名称 / Base URL 改得动。
//
// 对应两个真实缺陷：预设不补齐，用户就得手打三个长地址和模型名；
// 内置项一旦锁字段，想换成自己的网关只能整个删掉重建。

import 'dart:convert';

import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/ai/ai_provider_manage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 表单一屏放不下，给足高度，否则 ListView 不会构建模型输入框。
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AIProviderManagePage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// LoggerService 落盘有 2 秒防抖 Timer，不排掉的话测试会因为 timersPending 判失败。
  Future<void> drainLoggerTimer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> openEditor(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  /// 只认输入框当前的值：预设的 hintText 也等于默认模型名，
  /// 用 widgetWithText 判会把 hint 那份也数进去。
  Finder fieldShowing(WidgetTester tester, String text) => find
      .byWidgetPredicate((w) => w is EditableText && w.controller.text == text);

  /// 往当前值为 [oldText] 的输入框里替换成 [newText]。
  Future<void> replaceText(
      WidgetTester tester, String oldText, String newText) async {
    final field = fieldShowing(tester, oldText);
    expect(field, findsOneWidget, reason: '没有唯一显示 $oldText 的输入框');
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, newText);
    await tester.pumpAndSettle();
  }

  testWidgets('预设全部进列表，都标内置，也没有删除按钮', (tester) async {
    await pumpPage(tester);

    expect(find.text('智谱GLM'), findsWidgets);
    expect(find.text('Requesty 免费池'), findsOneWidget);
    expect(find.text('小红书点点'), findsOneWidget);
    expect(find.text('书生·端砚'), findsOneWidget);
    expect(find.text('Kilo 免费池'), findsOneWidget);
    expect(find.text('内置'), findsNWidgets(5));
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await drainLoggerTimer(tester);
  });

  testWidgets('预设卡片上写着实测到的限流与留存说明', (tester) async {
    await pumpPage(tester);

    expect(find.textContaining('免费多模态'), findsOneWidget);
    expect(find.textContaining('15 次/分钟'), findsOneWidget);
    expect(find.textContaining('目前只有它支持'), findsOneWidget);
    expect(find.textContaining('不扣墨点'), findsOneWidget);
    expect(find.textContaining('反向工程'), findsOneWidget);
    await drainLoggerTimer(tester);
  });

  testWidgets('内置项的名称和 Base URL 改得动，保存后按 id 存回', (tester) async {
    await pumpPage(tester);
    await openEditor(tester, 'Requesty 免费池');

    expect(
        fieldShowing(tester, 'https://router.requesty.ai/v1'), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);

    await replaceText(tester, 'Requesty 免费池', '我的免费池');
    await replaceText(tester, 'https://router.requesty.ai/v1',
        'https://my-gateway.example.com/v1');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = (jsonDecode(prefs.getString('ai_providers_v2')!) as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] == 'requesty_free');
    expect(saved['name'], '我的免费池');
    expect(saved['baseUrl'], 'https://my-gateway.example.com/v1');
    // 改过名字的预设不能被当成"缺失"再补一份回来
    final ids = (jsonDecode(prefs.getString('ai_providers_v2')!) as List)
        .map((p) => (p as Map)['id']);
    expect(ids.where((id) => id == 'requesty_free').length, 1);
    await drainLoggerTimer(tester);
  });

  testWidgets('点候选模型 chip 直接把模型名填进输入框', (tester) async {
    await pumpPage(tester);
    await openEditor(tester, '智谱GLM');

    expect(fieldShowing(tester, 'glm-4-flash'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'glm-4.7-flash'));
    await tester.pumpAndSettle();

    expect(fieldShowing(tester, 'glm-4.7-flash'), findsOneWidget);
    await drainLoggerTimer(tester);
  });

  testWidgets('自建服务商没有恢复默认，也仍然可以删', (tester) async {
    await AIProviderManager.addProvider(
      name: '自建网关',
      apiKey: 'sk-test',
      baseUrl: 'https://internal.example.com/v1',
      textModel: 'some-model',
    );
    await pumpPage(tester);

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await openEditor(tester, '自建网关');
    expect(find.text('恢复默认'), findsNothing);
    await drainLoggerTimer(tester);
  });
}
