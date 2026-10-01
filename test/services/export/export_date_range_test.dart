// 导出时间段筛选的行为锁定。
//
// 最容易出错的三件事：不传日期必须跟旧版全量导出完全一致（回归安全）；
// 起止都是「整日」语义——起从当天 0 点算起、止包含当天整天（用户选了「9月30日」
// 就不会漏掉 30 号白天记的那笔）；只设一侧就只裁那一侧。

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations_zh.dart';
import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  /// 本测试造的交易不带分类、默认列也没勾分类列，取数路径不会真用 context；
  /// 给个假实现让 service 构造过得去即可。
  final _context = _FakeBuildContext();

  TransactionExportService service() =>
      TransactionExportService(repository: repo, l10n: AppLocalizationsZh(), context: _context);

  Future<void> seed() async {
    final ledgerId = await repo.createLedger(name: '测试账本');
    await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 10,
        happenedAt: DateTime(2026, 9, 1, 12));
    await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 20,
        happenedAt: DateTime(2026, 9, 15, 8));
    await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 30,
        happenedAt: DateTime(2026, 9, 30, 23, 59));
  }

  test('不传日期 = 全量导出，跟旧版一致', () async {
    await seed();
    final svc = service();
    final ledgerId = await repo.getAllLedgers().then((ls) => ls.first.id);
    final sheet = await svc.buildSheet(ledgerId);
    expect(sheet.dataRowCount, 3);
  });

  test('起止整日：起从当天 0 点、止含当天整天', () async {
    await seed();
    final svc = service();
    final ledgerId = await repo.getAllLedgers().then((ls) => ls.first.id);
    final sheet = await svc.buildSheet(
      ledgerId,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
    );
    // 9/1 中午那笔算「9月1日起」；9/30 晚 23:59 那笔必须被止日整天收住。
    expect(sheet.dataRowCount, 3);
  });

  test('只设止日 = 从最早记到止日整天', () async {
    await seed();
    final svc = service();
    final ledgerId = await repo.getAllLedgers().then((ls) => ls.first.id);
    final sheet = await svc.buildSheet(
      ledgerId,
      endDate: DateTime(2026, 9, 15),
    );
    expect(sheet.dataRowCount, 2, reason: '9/1 与 9/15 两笔都在止日内');
  });

  test('只设起日 = 起日整天往后全部', () async {
    await seed();
    final svc = service();
    final ledgerId = await repo.getAllLedgers().then((ls) => ls.first.id);
    final sheet = await svc.buildSheet(
      ledgerId,
      startDate: DateTime(2026, 9, 16),
    );
    expect(sheet.dataRowCount, 1, reason: '只剩 9/30 那笔');
  });

  test('区间外没有任何交易时，只剩表头一行', () async {
    await seed();
    final svc = service();
    final ledgerId = await repo.getAllLedgers().then((ls) => ls.first.id);
    final sheet = await svc.buildSheet(
      ledgerId,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
    );
    expect(sheet.dataRowCount, 0);
    expect(sheet.rows.length, 1);
  });
}

/// service 要的 context 只在「按 key 翻译分类名」时用；本测试交易不带分类，
/// 这个假实现只需存在、不接方法即可。
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('本测试取数路径不应真正使用 context');
}
