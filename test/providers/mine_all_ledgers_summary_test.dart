// 「我的」页全部账本汇总区的数据口径。
//
// 用户场景是三个账本，要在页面上看到跨账本的总笔数和总结余。这里锁两件事：
// ① 汇总必须真的覆盖所有账本，而不是只算当前那本；
// ② 结余是逐本相加，不能再乘一次汇率 —— getLedgerStats 读的是 nativeAmount，
//    已经折算过，套第二层会得出偏大的错数。

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers/currency_providers.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/statistics_providers.dart';
import 'package:beecount/providers/ui_state_providers.dart';
import 'package:beecount/services/data_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // importData 会走 LoggerService，测试环境必须给 shared_preferences mock。
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      accountFeatureEnabledProvider.overrideWith((ref) => Future.value(false)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> addTx(int ledgerId,
      {required String type, required double amount}) async {
    await DataImportService().importData(
      repo,
      ledgerId,
      ImportData(
        transactions: [
          ImportTransaction(
            type: type,
            amount: amount,
            categoryName: '测试',
            categoryKind: type == 'income' ? 'income' : 'expense',
            happenedAt: DateTime(2026, 9, 1, 12),
          ),
        ],
      ),
    );
  }

  test('三个账本的总笔数与总结余跨本累加', () async {
    final a = await repo.createLedger(name: '日常');
    final b = await repo.createLedger(name: '旅行');
    final c = await repo.createLedger(name: '生意');
    await addTx(a, type: 'income', amount: 100);
    await addTx(a, type: 'expense', amount: 30);
    await addTx(b, type: 'income', amount: 50);
    await addTx(c, type: 'expense', amount: 20);

    final container = makeContainer();
    final counts = await container.read(countsAllProvider.future);
    final balance = await container.read(allLedgersBalanceProvider.future);

    expect(counts.txCount, 4, reason: '要覆盖三个账本，不能只算当前本');
    // 100 - 30 + 50 - 20
    expect(balance, 100.0);
  });

  test('只有一个账本时汇总等于该账本自身', () async {
    final only = await repo.createLedger(name: '唯一');
    await addTx(only, type: 'income', amount: 88);
    await addTx(only, type: 'expense', amount: 8);

    final container = makeContainer();
    final single = await container.read(
        currentBalanceProvider(only).future);

    expect(single, 80.0);
    expect(await container.read(allLedgersBalanceProvider.future), single,
        reason: '单账本时汇总不应产生偏移');
  });

  test('空账本不影响汇总数字', () async {
    final a = await repo.createLedger(name: '有数据');
    await repo.createLedger(name: '空的');
    await addTx(a, type: 'income', amount: 66);

    final container = makeContainer();
    expect(await container.read(allLedgersBalanceProvider.future), 66.0);
    expect((await container.read(countsAllProvider.future)).txCount, 1);
  });

  test('结余为负时汇总如实反映（支出于收入）', () async {
    final a = await repo.createLedger(name: 'A');
    final b = await repo.createLedger(name: 'B');
    await addTx(a, type: 'expense', amount: 100);
    await addTx(b, type: 'income', amount: 40);

    final container = makeContainer();
    expect(await container.read(allLedgersBalanceProvider.future), -60.0);
  });

  test('改主币种不会让汇总重复折算', () async {
    // 各本 balance 已是 nativeAmount 口径，汇总只是相加；主币种从 CNY 换到 USD
    // 不应该让同一个结余被再乘一次汇率而翻倍。
    final a = await repo.createLedger(name: 'A', currency: 'USD');
    await addTx(a, type: 'income', amount: 120);

    final container = makeContainer();
    final asCny = await container.read(allLedgersBalanceProvider.future);
    container.read(baseCurrencyProvider.notifier).state = 'USD';
    final asUsd = await container.read(allLedgersBalanceProvider.future);

    expect(asCny, 120.0);
    expect(asUsd, asCny, reason: '汇总不做二次折算，币种切换不该改变它');
  });

  test('perLedgerStatsProvider 逐本返回天数/笔数/结余并带账本名', () async {
    final a = await repo.createLedger(name: '日常');
    final b = await repo.createLedger(name: '旅行');
    await addTx(a, type: 'income', amount: 100);
    await addTx(a, type: 'expense', amount: 30);
    await addTx(b, type: 'expense', amount: 20);

    final container = makeContainer();
    final per = await container.read(perLedgerStatsProvider.future);

    expect(per, hasLength(2));
    final byName = {for (final e in per) e.name: e};
    expect(byName['日常']!.txCount, 2);
    expect(byName['日常']!.balance, 70.0);
    expect(byName['旅行']!.txCount, 1);
    expect(byName['旅行']!.balance, -20.0);
  });
}
