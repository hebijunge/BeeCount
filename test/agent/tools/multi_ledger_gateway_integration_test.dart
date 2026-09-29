// 跨账本查询的真实链路。
//
// 工具层那批用例用的是 fake gateway，只能证明「参数确实传下去了」，证明不了统计 SQL
// 改成 ledger_id IN (...) 之后真能查回多个账本的数据。这里用真 drift 库 + 真 gateway
// 补上这一段。

import 'package:beecount/agent/memory/local_agent_memory_repository.dart';
import 'package:beecount/agent/tools/local_agent_tools.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';
import 'package:beecount/services/data_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late BeeCountLocalAgentToolGateway gateway;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    gateway = BeeCountLocalAgentToolGateway(
      repository: repo,
      database: db,
      baseCurrency: () => 'CNY',
      bookkeeper: AiBookkeeper(
        repository: repo,
        engine: const DefaultAiExtractionEngine(),
        persister: BillCreationService(repo),
      ),
      memoryRepository: LocalAgentMemoryRepository(db),
    );
  });

  tearDown(() async => db.close());

  Future<void> addTx(
    int ledgerId, {
    required String type,
    required double amount,
    required String note,
  }) async {
    await DataImportService().importData(
      repo,
      ledgerId,
      ImportData(
        transactions: [
          ImportTransaction(
            type: type,
            amount: amount,
            categoryName: '测试分类',
            categoryKind: type == 'income' ? 'income' : 'expense',
            happenedAt: DateTime(2026, 9, 10, 12),
            note: note,
          ),
        ],
      ),
    );
  }

  Future<Map<String, Object?>> summarize(
    List<int> ledgerIds, {
    Set<String> types = const {'income', 'expense', 'transfer'},
  }) =>
      gateway.summarizeTransactions(
        ledgerIds: ledgerIds,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 1),
        types: types,
        groupBy: 'none',
        categoryLevel: 'leaf',
        categoryIds: const [],
        categoryNames: const [],
        tagIds: const [],
        tagNames: const [],
        accountIds: const [],
        accountNames: const [],
        includeExcludedFromStats: false,
        groupLimit: 20,
      );

  Future<int> makeLedger(String name, {String currency = 'CNY'}) =>
      repo.createLedger(name: name, currency: currency);

  group('真库跨账本查询', () {
    test('明细查询能同时取回多个账本的交易', () async {
      final a = await makeLedger('日常');
      final b = await makeLedger('生意');
      await addTx(a, type: 'income', amount: 100, note: '工资');
      await addTx(a, type: 'expense', amount: 30, note: '午饭');
      await addTx(b, type: 'expense', amount: 500, note: '进货');

      final rows = await gateway.queryTransactions(
        ledgerIds: [a, b],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 1),
      );

      expect(rows, hasLength(3));
      expect(rows.map((row) => row.ledgerId).toSet(), {a, b});
    });

    test('只传一个账本时不会漏进别的账本数据', () async {
      final a = await makeLedger('日常');
      final b = await makeLedger('生意');
      await addTx(a, type: 'income', amount: 100, note: '工资');
      await addTx(b, type: 'income', amount: 9999, note: '不该出现');

      final rows = await gateway.queryTransactions(
        ledgerIds: [a],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 1),
      );

      expect(rows, hasLength(1));
      expect(rows.single.ledgerId, a);
      expect(rows.single.note, '工资');
    });

    test('跨账本统计把多本的金额加总', () async {
      final a = await makeLedger('日常');
      final b = await makeLedger('生意');
      await addTx(a, type: 'expense', amount: 30, note: '午饭');
      await addTx(b, type: 'expense', amount: 500, note: '进货');

      final result = await summarize([a, b], types: const {'expense'});
      final totals = result['totals'] as Map;
      final expense = totals['expense'] as Map;

      expect(expense['amount'], 530.0);
      expect(expense['count'], 2);
    });

    test('单账本统计的 currency 仍是该账本本位币', () async {
      final usd = await makeLedger('美元本', currency: 'USD');
      await addTx(usd, type: 'expense', amount: 20, note: '买');

      final result = await summarize([usd], types: const {'expense'});
      expect(result['currency'], 'USD');
    });

    test('跨账本统计的 currency 取主币种而不是某一本的', () async {
      final cny = await makeLedger('人民币本', currency: 'CNY');
      final usd = await makeLedger('美元本', currency: 'USD');
      await addTx(cny, type: 'expense', amount: 10, note: 'a');
      await addTx(usd, type: 'expense', amount: 20, note: 'b');

      final result = await summarize([cny, usd], types: const {'expense'});
      expect(result['currency'], 'CNY',
          reason: '多本币种不同，不能拿其中任意一本冒充');
    });

    test('跨账本统计即使不分组也附带 byLedger 拆分', () async {
      // 模型不总会在多本查询时选 groupBy=ledger，真模型实测过它会把合并总数同时
      // 报给每一本。所以拆分数字由服务端无条件给出。
      final a = await makeLedger('日常');
      final b = await makeLedger('生意');
      await addTx(a, type: 'expense', amount: 30, note: '午饭');
      await addTx(b, type: 'expense', amount: 500, note: '进货');

      final result = await summarize([a, b], types: const {'expense'});
      expect((result['totals'] as Map)['expense'],
          {'amount': 530.0, 'count': 2});

      final byLedger = (result['byLedger'] as List).cast<Map<String, Object?>>();
      expect(byLedger, hasLength(2));
      final byName = {
        for (final group in byLedger)
          (group['key'] as Map)['name'] as String:
              ((group['totals'] as Map)['expense'] as Map)['amount'],
      };
      expect(byName['日常'], 30.0);
      expect(byName['生意'], 500.0);
    });

    test('单账本统计不附带 byLedger', () async {
      final a = await makeLedger('日常');
      await addTx(a, type: 'expense', amount: 30, note: '午饭');

      final result = await summarize([a], types: const {'expense'});
      expect(result.containsKey('byLedger'), isFalse);
    });

    test('groupBy=ledger 时按账本拆开，不给合并总数', () async {
      // 真模型实测过：一次查两本又只拿合并数时，模型会把总数安到其中一本头上、
      // 另一本报 0。分组必须在数据库里做，不能让模型靠多次调用去猜。
      final a = await makeLedger('日常');
      final b = await makeLedger('生意');
      await addTx(a, type: 'expense', amount: 30, note: '午饭');
      await addTx(b, type: 'expense', amount: 500, note: '进货');

      final result = await gateway.summarizeTransactions(
        ledgerIds: [a, b],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 1),
        types: const {'expense'},
        groupBy: 'ledger',
        categoryLevel: 'leaf',
        categoryIds: const [],
        categoryNames: const [],
        tagIds: const [],
        tagNames: const [],
        accountIds: const [],
        accountNames: const [],
        includeExcludedFromStats: false,
        groupLimit: 20,
      );

      final groups = (result['groups'] as List).cast<Map<String, Object?>>();
      expect(groups, hasLength(2));
      final byName = {
        for (final group in groups)
          (group['key'] as Map)['name'] as String:
              ((group['totals'] as Map)['expense'] as Map)['amount'],
      };
      expect(byName['日常'], 30.0);
      expect(byName['生意'], 500.0);
    });

    test('预算跨账本时逐本返回并标注归属', () async {
      final a = await makeLedger('日常');
      final b = await makeLedger('生意');

      final items = await gateway.getBudgetStatus([a, b]);
      expect(items, hasLength(2));
      expect(items.map((item) => item.ledgerName), containsAll(['日常', '生意']));
    });

    test('预算单本查询不额外标注归属，保持原输出契约', () async {
      final a = await makeLedger('日常');
      final items = await gateway.getBudgetStatus([a]);
      expect(items.single.ledgerName, isNull);
    });

    test('账本清单含 id、名称与本位币', () async {
      await makeLedger('日常');
      await makeLedger('美元本', currency: 'USD');

      final catalog = await gateway.getLedgerCatalog();
      expect(catalog, hasLength(2));
      expect(catalog.map((l) => l.name), ['日常', '美元本']);
      expect(catalog.map((l) => l.currency), ['CNY', 'USD']);
      expect(catalog.every((l) => l.id > 0), isTrue);
    });
  });
}
