import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> addTx(int ledgerId, DateTime at) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 10,
            happenedAt: d.Value(at),
          ));

  test('跨账本聚合:取选中账本合起来的最早/最晚一笔', () async {
    await addTx(1, DateTime(2026, 3, 1));
    await addTx(2, DateTime(2026, 1, 5)); // 选中账本里最早
    await addTx(2, DateTime(2026, 9, 30)); // 选中账本里最晚
    await addTx(3, DateTime(2025, 1, 1)); // 未选中，不能参与
    await addTx(3, DateTime(2027, 12, 31));

    final (earliest, latest) = await repo.getTransactionTimeRange([1, 2]);
    expect(earliest, DateTime(2026, 1, 5));
    expect(latest, DateTime(2026, 9, 30));
  });

  test('单账本也能拿到两端', () async {
    await addTx(1, DateTime(2026, 6, 10));
    await addTx(1, DateTime(2026, 6, 1));

    final (earliest, latest) = await repo.getTransactionTimeRange([1]);
    expect(earliest, DateTime(2026, 6, 1));
    expect(latest, DateTime(2026, 6, 10));
  });

  test('空账本 / 没选账本时两端都是 null', () async {
    await addTx(9, DateTime(2026, 1, 1));

    expect(await repo.getTransactionTimeRange([1]), (null, null));
    expect(await repo.getTransactionTimeRange([]), (null, null));
  });
}
