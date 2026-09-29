// 多账本「分组导入」的落库验证。
//
// 用户的实际场景：原版软件里有三个账本，只能逐个导出（每个文件都是固定 12 列、
// 不含账本标识的 CSV），合并补上「账本」列后一次性导回新包。这里锁死两件事：
// 1) 带账本名的行必须落进对应账本，不能全堆进当前账本；
// 2) 不带账本名的行（旧格式、或该列留空）仍进当前账本，保持旧行为。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/data_import_service.dart';

void main() {
  // importData 内部用 logger（MethodChannel 桥），需要 binding 先初始化；
  // LoggerService 落盘走 shared_preferences，测试环境不给 mock 会抛出未 await 的
  // MissingPluginException，把已经断言通过的用例判成失败。
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late DataImportService svc;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    svc = DataImportService();
  });

  tearDown(() async => db.close());

  Future<int> txCount(int ledgerId) async =>
      (await (db.select(db.transactions)
            ..where((t) => t.ledgerId.equals(ledgerId)))
          .get())
          .length;

  /// 与 import_confirm_page 的分组循环同构：有账本名的按名找/建，没有的留当前账本。
  Future<void> importGrouped(
    int currentLedgerId,
    List<ImportTransaction> txs,
  ) async {
    final groups = <String?, List<ImportTransaction>>{};
    for (final tx in txs) {
      final raw = tx.ledgerName?.trim() ?? '';
      groups.putIfAbsent(raw.isEmpty ? null : raw, () => []).add(tx);
    }
    for (final entry in groups.entries) {
      final target = entry.key == null
          ? currentLedgerId
          : await svc.ensureLedgerByName(repo, entry.key!);
      final result = await svc.importData(
        repo,
        target,
        ImportData(transactions: entry.value),
        defaultCurrency: 'CNY',
      );
      expect(result.failed, 0, reason: '账本「${entry.key}」有行导入失败');
    }
  }

  ImportTransaction tx(String name, {String? ledgerName}) => ImportTransaction(
        type: 'expense',
        amount: 10.0,
        categoryName: name,
        categoryKind: 'expense',
        happenedAt: DateTime(2026, 9, 1, 12),
        note: name,
        ledgerName: ledgerName,
      );

  test('三个账本各自归位，不落到当前账本', () async {
    final current = await repo.createLedger(name: '默认');
    await importGrouped(current, [
      tx('午餐', ledgerName: '日常'),
      tx('餐饮', ledgerName: '日常'),
      tx('交通', ledgerName: '日常'),
      tx('机票', ledgerName: '旅行 2026'),
      tx('酒店', ledgerName: '旅行 2026'),
      tx('房租', ledgerName: '房租'),
    ]);

    final ledgers = await repo.getAllLedgers();
    expect(ledgers, hasLength(4), reason: '当前账本 + 三个来源账本');

    final byName = {for (final l in ledgers) l.name: l.id};
    expect(await txCount(byName['日常']!), 3);
    expect(await txCount(byName['旅行 2026']!), 2);
    expect(await txCount(byName['房租']!), 1);
    expect(await txCount(current), 0, reason: '不该再全堆进当前账本');
  });

  test('不带账本列的旧格式仍整体进当前账本', () async {
    final current = await repo.createLedger(name: '默认');
    await importGrouped(current, [tx('午餐'), tx('交通')]);

    expect(await repo.getAllLedgers(), hasLength(1),
        reason: '无归属信息时不能凭空建账本');
    expect(await txCount(current), 2);
  });

  test('账本名与当前账本相同时不分裂成两本', () async {
    final current = await repo.createLedger(name: '日常');
    await importGrouped(current, [
      tx('午餐', ledgerName: '日常'),
      tx('交通', ledgerName: '日常'),
    ]);

    expect(await repo.getAllLedgers(), hasLength(1),
        reason: '同名必须复用，不能静默建出重复账本');
    expect(await txCount(current), 2);
  });

  test('部分行缺账本名时，缺的那部分进当前账本', () async {
    final current = await repo.createLedger(name: '默认');
    await importGrouped(current, [
      tx('午餐', ledgerName: '日常'),
      tx('手工补记'),
      tx('空白列', ledgerName: '   '),
    ]);

    final byName = {for (final l in await repo.getAllLedgers()) l.name: l.id};
    expect(byName.keys, containsAll(<String>['默认', '日常']));
    expect(await txCount(byName['日常']!), 1);
    expect(await txCount(current), 2, reason: 'null 与空白串都算无归属');
  });
}
