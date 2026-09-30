// 「工程/维修」预设包的行为契约。
//
// 内置默认包是消费型的（餐饮/交通/服饰…），工程采购和上门维修的账本在里面找不到落点。
// 这里锁四件事：四个语言都能解析出真实分类名（不许 fallback 成 snake_case key）、
// 支出 8 类 + 收入 3 类、重复点不堆出第二份、跟默认包混着点也不产生同名重复。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/services/data/seed_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const locales = [
    Locale('zh'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('ko'),
  ];
  // 解析失败会返回 key 本身，正常分类名不会是全小写下划线串。
  final fallbackPattern = RegExp(r'^[a-z][a-z_]*$');

  for (final locale in locales) {
    final tag = locale.toLanguageTag();

    test('工程/维修包解析出真实分类名，支出 8 类收入 3 类 [$tag]', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final db = BeeDatabase.forTesting(NativeDatabase.memory());
      final repo = LocalRepository(db);
      try {
        expect(
          await SeedService.addProjectRepairCategories(
              repository: repo, l10n: l10n, kind: 'expense'),
          8,
        );
        expect(
          await SeedService.addProjectRepairCategories(
              repository: repo, l10n: l10n, kind: 'income'),
          3,
        );

        final cats = await db.select(db.categories).get();
        expect(cats, hasLength(11));
        expect(
          cats.map((c) => c.name).where((n) => fallbackPattern.hasMatch(n)),
          isEmpty,
          reason: '有分类名没解析出来，落成了 key',
        );
        // 一级分类，父级为空：这个包不预设二级，怎么拆跟工种有关。
        expect(cats.every((c) => c.parentId == null && c.level == 1), isTrue);
      } finally {
        await db.close();
      }
    });

    test('重复点不会堆出第二份 [$tag]', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final db = BeeDatabase.forTesting(NativeDatabase.memory());
      final repo = LocalRepository(db);
      try {
        final first = await SeedService.addProjectRepairCategories(
            repository: repo, l10n: l10n, kind: 'expense');
        final again = await SeedService.addProjectRepairCategories(
            repository: repo, l10n: l10n, kind: 'expense');

        expect(first, 8);
        expect(again, 0, reason: '第二次应当全部跳过');
        expect(await db.select(db.categories).get(), hasLength(8));
      } finally {
        await db.close();
      }
    });
  }

  test('跟默认包混着点也不产生同名重复', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    final repo = LocalRepository(db);
    try {
      await SeedService.addDefaultCategories(
        repository: repo,
        l10n: l10n,
        kind: 'expense',
        hierarchical: false,
      );
      await SeedService.addProjectRepairCategories(
          repository: repo, l10n: l10n, kind: 'expense');

      final names = (await db.select(db.categories).get())
          .map((c) => '${c.name}|${c.kind}')
          .toList();
      expect(names.toSet(), hasLength(names.length), reason: '出现同名重复分类');
      expect(names, containsAll(['建材|expense', '五金|expense', '人工|expense']));
    } finally {
      await db.close();
    }
  });
}
