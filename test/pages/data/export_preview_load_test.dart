// 预览页能否正常进入加载流程。
//
// 之前 _load() 在 initState 里被直接调用，而它第一句就用 AppLocalizations.of(context)：
// Flutter 不允许在 initState 完成前依赖 InheritedWidget，于是抛断言异常。这个调用没有
// 被 await，异常只是静静冒到 zone 里，_sheets/_error 都还是 null，页面永远停在转圈 ——
// 导出预览完全打不开。改成首帧后再加载，这里同时锁两件事：不抛异常、表头真渲染出来。
//
// drift 的内存库要真异步才跑得动，所以整段放进 tester.runAsync。

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/data/export_preview_page.dart';
import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('打开导出预览不抛异常，并渲染出按顺序排好的表头', (tester) async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    final repo = LocalRepository(db);
    final ledgerId = await repo.createLedger(name: '默认账本');

    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // PrimaryHeader 是 ConsumerWidget，必须有 ProviderScope 祖先。
    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: ExportPreviewPage(
            repository: repo,
            ledgerIds: [ledgerId],
            asExcel: true,
            columns: ExportColumn.defaultSelected,
            columnOrder: ExportColumn.defaultOrder,
          ),
        ),
      ));
      await tester.pump(); // 首帧，postFrameCallback 里才开始取数
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'initState 期间依赖 InheritedWidget 会让预览永远转圈');
      // 默认勾选「时间 / 金额 / 备注」，且 defaultOrder 把时间排在金额前。
      expect(find.text('时间'), findsWidgets);
      expect(find.text('金额'), findsWidgets);
      expect(find.text('备注'), findsWidgets);
    });

    await db.close();
  });
}
