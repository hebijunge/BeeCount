// 真模型跨账本验证。默认跳过，需要显式给 key：
//
//   ZHIPU_API_KEY=*** flutter test test/agent/multi_ledger_agent_live_test.dart
//
// 离线那批用例已经证明「参数能传下去」和「真 SQL 能查回多本数据」，这里只补最后一环：
// 模型自己会不会去用这个能力。断言点是它发出的工具调用里带了哪几本 —— 问「把生意和
// 旅行分别列出来」时，它应该从上下文账本清单里挑出这两本的 id。
//
// 写账那一条同理：离线用例只能证明「传了国宇就写国宇」，证明不了模型会不会把用户嘴里
// 的「国宇」填进 ledgerName。所以那条既看工具参数，也直接查库确认钱落对了本子。
//
// key 只从环境变量读，不落盘、不进提交。

import 'dart:io';

import 'package:agentcore/agentcore.dart';
import 'package:beecount/agent/memory/local_agent_memory_repository.dart';
import 'package:beecount/agent/tools/local_agent_tools.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/agent_app_facade.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';
import 'package:beecount/services/data_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // TestWidgetsFlutterBinding 会装一层 HttpOverrides，让所有请求直接返回 400 且
  // 根本不联网（跑测试时那条 warning 就是它）。这一条要真打智谱，所以摘掉。
  HttpOverrides.global = null;

  final apiKey = (Platform.environment['ZHIPU_API_KEY'] ?? '').trim();

  test('模型能从账本清单里挑出指定的两本做跨账本统计', () async {
    if (apiKey.isEmpty) {
      markTestSkipped('未提供 ZHIPU_API_KEY，跳过真模型验证');
      return;
    }

    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalRepository(db);

    final daily = await repo.createLedger(name: '日常');
    final business = await repo.createLedger(name: '生意');
    final travel = await repo.createLedger(name: '旅行');
    await _expense(repo, daily, 30, '午饭');
    await _expense(repo, business, 500, '进货');
    await _expense(repo, travel, 1200, '机票');

    final config = AIServiceProviderConfig.zhipuDefault;
    await _useZhipuTextModel(apiKey, config);

    final gateway = BeeCountLocalAgentToolGateway(
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
    final recorder = _RecordingGateway(gateway);
    final facade = AgentAppFacade(
      memoryRepository: LocalAgentMemoryRepository(db),
      toolGateway: recorder,
      permissionStore: _AllowAllPermissions(),
      runIdFactory: () => 'live-multi-ledger',
    );

    final response = await facade.processMessage(
      message: '把生意和旅行这两个账本九月的支出分别列出来',
      ledgerId: daily,
    );

    // ignore: avoid_print
    print('模型回答: ${response.text}');
    // ignore: avoid_print
    print('统计工具收到的账本范围: ${recorder.summaryLedgerIds}');
    // ignore: avoid_print
    print('明细工具收到的账本范围: ${recorder.queryLedgerIds}');

    expect(response.type, isNot('error'), reason: response.text);
    final covered = {
      ...recorder.summaryLedgerIds.expand((ids) => ids),
      ...recorder.queryLedgerIds.expand((ids) => ids),
    };
    expect(covered, containsAll(<int>[business, travel]),
        reason: '模型没把这两本的 id 传进 ledgerIds，说明上下文清单没起作用');
    // 光传对 id 还不够：曾经出现过一次查两本、把合并总数 1700 整个安到旅行头上、
    // 给生意报 0 的情况。数字必须各自落对。
    expect(response.text, contains('500'),
        reason: '生意账本的支出没有正确报出');
    expect(response.text, contains('1200'),
        reason: '旅行账本的支出没有正确报出');
    expect(response.text, isNot(contains('0元，旅行账本在九月的支出总额为1700')),
        reason: '又退化成把合并总数安到一本头上');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('模型点名账本时，这笔记进被点名的那本而不是当前账本', () async {
    if (apiKey.isEmpty) {
      markTestSkipped('未提供 ZHIPU_API_KEY，跳过真模型验证');
      return;
    }

    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalRepository(db);

    // 当前账本故意停在华恒远：只要这笔没走 ledgerName 解析，就会落在这里被测试抓到。
    final huaheng = await repo.createLedger(name: '华恒远');
    final guoyu = await repo.createLedger(name: '国宇');

    await _useZhipuTextModel(apiKey, AIServiceProviderConfig.zhipuDefault);

    final gateway = BeeCountLocalAgentToolGateway(
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
    final recorder = _RecordingGateway(gateway);
    final facade = AgentAppFacade(
      memoryRepository: LocalAgentMemoryRepository(db),
      toolGateway: recorder,
      permissionStore: _AllowAllPermissions(),
      runIdFactory: () => 'live-record-into-named-ledger',
    );

    final response = await facade.processMessage(
      message: '给国宇买白结构胶一箱150',
      ledgerId: huaheng,
    );

    // ignore: avoid_print
    print('模型回答: ${response.text}');
    // ignore: avoid_print
    print('记账工具收到的账本: ${recorder.recordRequests}');

    expect(response.type, isNot('error'), reason: response.text);
    expect(recorder.recordRequests, hasLength(1), reason: '模型没调用记账工具');
    expect(recorder.recordRequests.single.ledgerId, guoyu,
        reason: '这笔没被解析到国宇，说明 ledgerName 那条链路没走通');

    // 工具参数传对还不算完：钱得真落进那本账，且金额、类型、备注对得上。
    final inGuoyu = await repo
        .getRecentTransactionsWithCategory(ledgerId: guoyu, limit: 10);
    final inHuaheng = await repo
        .getRecentTransactionsWithCategory(ledgerId: huaheng, limit: 10);

    expect(inGuoyu, hasLength(1));
    expect(inHuaheng, isEmpty, reason: '这笔漏进了当前账本，等于记错账');
    expect(inGuoyu.single.t.amount, 150);
    expect(inGuoyu.single.t.type, 'expense');
    expect(inGuoyu.single.t.note, contains('结构胶'),
        reason: '备注没留下买的东西，这笔账在国宇那本里说不清');
  }, timeout: const Timeout(Duration(minutes: 3)));

  /// 用户点名了一个本机没有的账本时，回执必须报出钱实际落在哪本。
  ///
  /// 工具层能锁住「点了清单里的名字却漏传 ledgerName」（回看 sourceText 就能查出来），
  /// 但「没点名」和「点了个清单外的名字」在省略 ledgerName 时是同一个信号，分不开 ——
  /// 真机活体测过三种写法：ledgerName 可选时模型对清单外的名字干脆不传；改成必填它就连
  /// 清单内的「国宇」都抄 current 的名称交差。所以这一条锁的不是"别写库"，而是"写进
  /// 当前账本时必须当场说清楚是哪本"，让用户有机会发现记错了本子。
  test('用户点名清单外的账本时，回执要报出实际落账的那本', () async {
    if (apiKey.isEmpty) {
      markTestSkipped('未提供 ZHIPU_API_KEY，跳过真模型验证');
      return;
    }

    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalRepository(db);

    final huaheng = await repo.createLedger(name: '华恒远');
    final guoyu = await repo.createLedger(name: '国宇');

    await _useZhipuTextModel(apiKey, AIServiceProviderConfig.zhipuDefault);

    final gateway = BeeCountLocalAgentToolGateway(
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
    final recorder = _RecordingGateway(gateway);
    final facade = AgentAppFacade(
      memoryRepository: LocalAgentMemoryRepository(db),
      toolGateway: recorder,
      permissionStore: _AllowAllPermissions(),
      runIdFactory: () => 'live-unknown-ledger',
    );

    final response = await facade.processMessage(
      message: '给蓝图买电钻380',
      ledgerId: huaheng,
    );

    // ignore: avoid_print
    print('模型回答: ${response.text}');
    // ignore: avoid_print
    print('记账工具收到的账本: ${recorder.recordRequests}');

    for (final ledgerId in [huaheng, guoyu]) {
      final rows = await repo.getRecentTransactionsWithCategory(
        ledgerId: ledgerId,
        limit: 10,
      );
      // 工具层区分不了「用户没点名」和「点了个清单外的名字」，这笔会落进当前账本。
      // 能锁住的是回执：钱落在哪本必须说出口，用户才有机会当场发现记错了本子。
      if (ledgerId == huaheng) {
        expect(response.text, contains('华恒远'),
            reason: '静默记进当前账本而不报名字，等于让用户以为记进了「蓝图」');
      } else {
        expect(rows, isEmpty, reason: '不该猜着记进别的账本');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// 真模型用例的公共前置。必须用 update 而不是 add：getProviders() 首次会先落一条空
/// key 的内置智谱，add 会变成同 id 两条，getProvider 的 firstWhere 命中那条空的，
/// 于是报「未配置可用的文本对话服务商」。
Future<void> _useZhipuTextModel(
  String apiKey,
  AIServiceProviderConfig config,
) async {
  await AIProviderManager.updateProvider(
    AIServiceProviderConfig(
      id: config.id,
      name: config.name,
      isBuiltIn: config.isBuiltIn,
      apiKey: apiKey,
      baseUrl: config.baseUrl,
      textModel: config.textModel,
      visionModel: config.visionModel,
      audioModel: config.audioModel,
      createdAt: config.createdAt,
    ),
  );
  await AIProviderManager.setCapabilityProvider(
    AICapabilityType.text,
    config.id,
  );
}

Future<void> _expense(
  LocalRepository repo,
  int ledgerId,
  double amount,
  String note,
) async {
  await DataImportService().importData(
    repo,
    ledgerId,
    ImportData(
      transactions: [
        ImportTransaction(
          type: 'expense',
          amount: amount,
          categoryName: '测试分类',
          categoryKind: 'expense',
          happenedAt: DateTime(2026, 9, 10, 12),
          note: note,
        ),
      ],
    ),
  );
}

/// 只为了看见模型传了什么账本范围，其余全部透传。
final class _RecordingGateway implements LocalAgentToolGateway {
  _RecordingGateway(this._inner);

  final LocalAgentToolGateway _inner;
  final List<List<int>> summaryLedgerIds = [];
  final List<List<int>> queryLedgerIds = [];
  final List<({int ledgerId, String text})> recordRequests = [];

  @override
  Future<List<AgentTransactionSummary>> queryTransactions({
    required List<int> ledgerIds,
    required DateTime start,
    required DateTime end,
  }) {
    queryLedgerIds.add(ledgerIds);
    return _inner.queryTransactions(
      ledgerIds: ledgerIds,
      start: start,
      end: end,
    );
  }

  @override
  Future<Map<String, Object?>> summarizeTransactions({
    required List<int> ledgerIds,
    required DateTime start,
    required DateTime end,
    required Set<String> types,
    required String groupBy,
    required String categoryLevel,
    required List<int> categoryIds,
    required List<String> categoryNames,
    required List<int> tagIds,
    required List<String> tagNames,
    required List<int> accountIds,
    required List<String> accountNames,
    required bool includeExcludedFromStats,
    required int groupLimit,
  }) {
    summaryLedgerIds.add(ledgerIds);
    return _inner.summarizeTransactions(
      ledgerIds: ledgerIds,
      start: start,
      end: end,
      types: types,
      groupBy: groupBy,
      categoryLevel: categoryLevel,
      categoryIds: categoryIds,
      categoryNames: categoryNames,
      tagIds: tagIds,
      tagNames: tagNames,
      accountIds: accountIds,
      accountNames: accountNames,
      includeExcludedFromStats: includeExcludedFromStats,
      groupLimit: groupLimit,
    );
  }

  @override
  Future<List<AgentLedgerSummary>> getLedgerCatalog() =>
      _inner.getLedgerCatalog();

  @override
  Future<String> getBaseCurrency() => _inner.getBaseCurrency();

  @override
  Future<String> getLedgerCurrency(int ledgerId) =>
      _inner.getLedgerCurrency(ledgerId);

  @override
  Future<List<AgentBudgetSummary>> getBudgetStatus(List<int> ledgerIds) =>
      _inner.getBudgetStatus(ledgerIds);

  @override
  Future<List<AgentRecurringTransactionSummary>> getRecurringTransactions(
    List<int> ledgerIds,
  ) =>
      _inner.getRecurringTransactions(ledgerIds);

  @override
  Future<AgentRecordToolResult> recordTransaction({
    required int ledgerId,
    required String text,
  }) {
    recordRequests.add((ledgerId: ledgerId, text: text));
    return _inner.recordTransaction(ledgerId: ledgerId, text: text);
  }

  @override
  Future<int> saveExplicitMemory({
    required int? ledgerId,
    required String content,
  }) =>
      _inner.saveExplicitMemory(ledgerId: ledgerId, content: content);

  @override
  Future<bool> forgetMemory({
    required int ledgerId,
    required int memoryId,
  }) =>
      _inner.forgetMemory(ledgerId: ledgerId, memoryId: memoryId);
}

final class _AllowAllPermissions implements AgentToolPermissionStore {
  final Map<String, AgentToolPermission> _granted = {};

  /// 返回 null 会被运行时当成「未授权」，模型因此拒绝调用工具。
  @override
  Future<AgentToolPermission?> permissionFor(String toolName) async =>
      _granted[toolName] ?? AgentToolPermission.alwaysAllow;

  @override
  Future<Map<String, AgentToolPermission>> readAll() async => {..._granted};

  @override
  Future<void> setPermission(
    String toolName,
    AgentToolPermission permission,
  ) async {
    _granted[toolName] = permission;
  }

  @override
  Future<void> restoreDefaults() async => _granted.clear();
}
