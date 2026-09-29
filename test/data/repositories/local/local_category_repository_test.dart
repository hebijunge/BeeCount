// 分类重名判定的作用域契约测试。
//
// 锁死:分类名只在「同一父级 + 同 kind」作用域内唯一 —— 一级之间不重名、同一父级下的
// 二级之间不重名;二级可以与任意一级(包括它自己的父级)同名,不同父级的二级之间也可同
// 名,跨 kind 始终允许同名。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('分类跨类型同名 (name, kind)', () {
    test('跨 kind 同名分类可共存(收入红包 + 支出红包)', () async {
      final inc = await repo.createCategory(name: '红包', kind: 'income');
      final exp = await repo.createCategory(name: '红包', kind: 'expense');
      expect(inc, isNot(exp));
    });

    test('同 kind 重名抛 DuplicateNameException', () async {
      await repo.createCategory(name: '红包', kind: 'expense');
      expect(
        () => repo.createCategory(name: '红包', kind: 'expense'),
        throwsA(isA<DuplicateNameException>()),
      );
    });

    test('isCategoryNameDuplicate 按 (name, kind) 判定', () async {
      await repo.createCategory(name: '红包', kind: 'expense');
      expect(
        await repo.isCategoryNameDuplicate(name: '红包', kind: 'expense'),
        isTrue,
      );
      expect(
        await repo.isCategoryNameDuplicate(name: '红包', kind: 'income'),
        isFalse,
      );
    });

    test('upsertCategory 跨 kind 不误复用、同 kind 复用', () async {
      final a = await repo.upsertCategory(name: '红包', kind: 'income');
      final b = await repo.upsertCategory(name: '红包', kind: 'expense');
      expect(a, isNot(b)); // 跨 kind → 建两个独立分类
      final aAgain = await repo.upsertCategory(name: '红包', kind: 'income');
      expect(aAgain, a); // 同 kind → 复用
    });

    test('createSubCategory 跨 kind 同名子分类可共存', () async {
      final pInc = await repo.createCategory(name: '工资', kind: 'income');
      final pExp = await repo.createCategory(name: '餐饮', kind: 'expense');
      final subInc =
          await repo.createSubCategory(parentId: pInc, name: '红包', kind: 'income');
      final subExp =
          await repo.createSubCategory(parentId: pExp, name: '红包', kind: 'expense');
      expect(subInc, isNot(subExp));
    });

    test('createSubCategory 同一父级下重名抛 DuplicateNameException', () async {
      final p = await repo.createCategory(name: '餐饮', kind: 'expense');
      await repo.createSubCategory(parentId: p, name: '午餐', kind: 'expense');
      expect(
        () => repo.createSubCategory(parentId: p, name: '午餐', kind: 'expense'),
        throwsA(isA<DuplicateNameException>()),
      );
    });
  });

  group('分类名按父级作用域判重', () {
    test('二级可以与别的一级同名', () async {
      final food = await repo.createCategory(name: '餐饮', kind: 'expense');
      final travel = await repo.createCategory(name: '出行', kind: 'expense');
      final sub = await repo.createSubCategory(
          parentId: travel, name: '餐饮', kind: 'expense');
      expect(sub, isNot(food));
      expect(sub, isNot(travel));
    });

    test('二级可以与自己的父级同名', () async {
      final food = await repo.createCategory(name: '餐饮', kind: 'expense');
      final sub = await repo.createSubCategory(
          parentId: food, name: '餐饮', kind: 'expense');
      expect(sub, isNot(food));
    });

    test('不同父级下的二级可以同名', () async {
      final p1 = await repo.createCategory(name: '出行', kind: 'expense');
      final p2 = await repo.createCategory(name: '日常', kind: 'expense');
      final c1 = await repo.createSubCategory(
          parentId: p1, name: '打车', kind: 'expense');
      final c2 = await repo.createSubCategory(
          parentId: p2, name: '打车', kind: 'expense');
      expect(c1, isNot(c2));
    });

    test('isCategoryNameDuplicate 只在目标父级作用域内命中', () async {
      final p1 = await repo.createCategory(name: '餐饮', kind: 'expense');
      await repo.createSubCategory(parentId: p1, name: '午餐', kind: 'expense');
      final p2 = await repo.createCategory(name: '日常', kind: 'expense');

      // 同一父级下重名 → 命中
      expect(
        await repo.isCategoryNameDuplicate(
            name: '午餐', kind: 'expense', parentId: p1),
        isTrue,
      );
      // 换一个父级就不算重名
      expect(
        await repo.isCategoryNameDuplicate(
            name: '午餐', kind: 'expense', parentId: p2),
        isFalse,
      );
      // 一级作用域里没有叫「午餐」的，二级名字不该冒出来
      expect(
        await repo.isCategoryNameDuplicate(name: '午餐', kind: 'expense'),
        isFalse,
      );
      // 一级作用域仍按一级比对
      expect(
        await repo.isCategoryNameDuplicate(name: '餐饮', kind: 'expense'),
        isTrue,
      );
    });

    test('upsertCategory 不复用挂在别处的一级同名二级', () async {
      final food = await repo.createCategory(name: '餐饮', kind: 'expense');
      final sub = await repo.createSubCategory(
          parentId: food, name: '外卖', kind: 'expense');
      final upserted = await repo.upsertCategory(name: '外卖', kind: 'expense');
      final created = await repo.getCategoryById(upserted);
      expect(created, isNotNull);
      // 它建的是 L1 行，所以必须新插一条一级，而不是复用那个二级
      expect(created!.parentId, isNull);
      expect(upserted, isNot(sub));
    });
  });
}
