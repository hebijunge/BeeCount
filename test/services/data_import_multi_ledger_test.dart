// 多账本导入的归属解析测试。
//
// 锁死 ensureLedgerByName：导入文件里的账本名必须能认回已有账本，认不出才新建。
// 这里最容易出的事故是「静默建出一个重复账本」——交易看着导入成功了，实际散落在
// 两个同名账本里，用户很难察觉。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/data_import_service.dart';
import 'package:beecount/services/export/xlsx_workbook_writer.dart';

void main() {
  // importData 内部会用到 logger（MethodChannel 桥），需要 binding 先初始化。
  // LoggerService 首次写日志会从 shared_preferences 载入历史，测试环境不给 mock
  // 会抛出未 await 的 MissingPluginException —— 交易其实已入库，用例却会被判失败。
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

  test('已有同名账本时复用，不新建', () async {
    final id = await repo.createLedger(name: '日常');
    expect(await svc.ensureLedgerByName(repo, '日常'), id);
    expect(await repo.getAllLedgers(), hasLength(1));
  });

  test('认得 xlsx 的 sheet 安全化名（超长账本名）', () async {
    final long = '很长的账本名称' * 8;
    final id = await repo.createLedger(name: long);
    // 导出写成 sheet 时名字已被安全化，导入拿到的就是那个变形后的字符串。
    final sheetName = safeSheetName(long, id);
    expect(sheetName, isNot(long));
    expect(await svc.ensureLedgerByName(repo, sheetName), id,
        reason: '按 sheet 名必须能认回原账本');
    expect(await repo.getAllLedgers(), hasLength(1),
        reason: '认不回就会静默建出重复账本');
  });

  test('认得含非法字符的 sheet 安全化名', () async {
    final id = await repo.createLedger(name: 'A/B:C');
    expect(await svc.ensureLedgerByName(repo, safeSheetName('A/B:C', id)), id);
    expect(await repo.getAllLedgers(), hasLength(1));
  });

  test('匹配忽略大小写', () async {
    final id = await repo.createLedger(name: 'Daily');
    expect(await svc.ensureLedgerByName(repo, 'daily'), id);
    expect(await repo.getAllLedgers(), hasLength(1));
  });

  test('名字对不上才新建，并沿用给定币种', () async {
    await repo.createLedger(name: '日常');
    final newId = await svc.ensureLedgerByName(repo, '生意', currency: 'TWD');
    final created =
        (await repo.getAllLedgers()).firstWhere((l) => l.id == newId);
    expect(created.name, '生意');
    expect(created.currency, 'TWD');
  });

  test('空账本名直接报错，不会建出无名账本', () async {
    expect(() => svc.ensureLedgerByName(repo, '   '),
        throwsA(isA<ArgumentError>()));
  });

  test('两个账本分组导入后交易各归各位', () async {
    final a = await repo.createLedger(name: '日常');
    final b = await repo.createLedger(name: '生意');

    final rows = [
      ('日常', '餐饮'),
      ('日常', '打车'),
      ('生意', '进货'),
    ];

    // 复刻确认页的分组导入：按每行的 ledgerName 解析目标账本，再分组写入。
    for (final name in {for (final r in rows) r.$1}) {
      final ledgerId = await svc.ensureLedgerByName(repo, name);
      final txs = rows
          .where((r) => r.$1 == name)
          .map((r) => ImportTransaction(
                type: 'expense',
                amount: 10.0,
                happenedAt: DateTime(2026, 1, 1),
                categoryName: r.$2,
                categoryKind: 'expense',
                ledgerName: r.$1,
              ))
          .toList();
      await svc.importData(repo, ledgerId, ImportData(transactions: txs));
    }

    Future<int> countIn(int ledgerId) async =>
        (await (db.select(db.transactions)
              ..where((t) => t.ledgerId.equals(ledgerId)))
            .get())
            .length;

    expect(await countIn(a), 2, reason: '「日常」应只拿到自己那两笔');
    expect(await countIn(b), 1, reason: '「生意」应只拿到一笔');
    expect(await repo.getAllLedgers(), hasLength(2), reason: '不该多建账本');
  });
}
