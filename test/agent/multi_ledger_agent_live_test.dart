// 真模型跨账本验证。默认跳过，需要显式给 key：
//
//   ZHIPU_API_KEY=*** flutter test test/agent/multi_ledger_agent_live_test.dart
//
// 离线那批用例已经证明「参数能传下去」和「真 SQL 能查回多本数据」，这里只补最后一环：
// 模型自己会不会去用这个能力。断言点是它发出的工具调用里带了哪几本 —— 问「把生意和
// 旅行分别列出来」时，它应该从上下文账本清单里挑出这两本的 id。
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
    // 必须用 update 而不是 add：getProviders() 首次会先落一条空 key 的内置智谱，
    // add 会变成同 id 两条，getProvider 的 firstWhere 命中那条空的，于是报
    // 「未配置可用的文本对话服务商」。
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
  }) =>
      _inner.recordTransaction(ledgerId: ledgerId, text: text);

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
