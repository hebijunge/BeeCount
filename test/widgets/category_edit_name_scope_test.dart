// 分类编辑页的重名作用域回归（对应上游 issue #482：二级分类与一级分类共用命名空间）。
//
// 锁死两件事：在某个一级分类下新建二级分类时，名字只与该父级下的兄弟比对 —— 与别的
// 一级同名必须能保存成功，不再弹「分类名称已存在」；同一父级下真重名仍然要拦住。

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/category/category_edit_page.dart';
import 'package:beecount/providers/database_providers.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;
  late Category travel;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await repo.createCategory(name: '餐饮', kind: 'expense');
    final travelId = await repo.createCategory(name: '出行', kind: 'expense');
    travel = (await repo.getCategoryById(travelId))!;
  });

  tearDown(() async => db.close());

  Widget host() {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        // ledgerId=0 时保存路径会跳过 PostProcessor.sync，不必装配云同步。
        currentLedgerIdProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: CategoryEditPage(kind: 'expense', parentCategory: travel),
      ),
    );
  }

  Future<void> typeAndSettle(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextFormField), name);
    // 输入框有 500ms 防抖判重，推进时钟让校验跑完再断言。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  testWidgets('二级分类与别的一级同名可保存，不判重', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await typeAndSettle(tester, '餐饮');
    expect(find.text('分类名称已存在'), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final rows = await repo.getAllCategories();
    expect(
      rows.where((c) => c.name == '餐饮' && c.parentId == travel.id),
      hasLength(1),
      reason: '应在「出行」底下建出与「餐饮」同名的二级分类',
    );

    // showToastOnOverlay 留了一个 2 秒移除计时器，推进掉避免泄漏。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('同一父级下的真重名仍然拦下', (tester) async {
    await repo.createSubCategory(
        parentId: travel.id, name: '打车', kind: 'expense');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await typeAndSettle(tester, '打车');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('分类名称已存在'), findsOneWidget);
    final rows = await repo.getAllCategories();
    expect(
      rows.where((c) => c.name == '打车' && c.parentId == travel.id),
      hasLength(1),
      reason: '被拦下后不应多插一行',
    );
  });
}
