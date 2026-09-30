import 'package:agentcore/agentcore.dart'
    hide
        AgentMemoryDraft,
        AgentMemoryRecord,
        AgentMemoryRepository,
        AgentToolCallAudit;

import '../../data/db.dart'
    show Account, BeeDatabase, Category, Ledger, Tag, Transaction;
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../services/ai/ai_bookkeeper.dart';
import '../../services/data/tag_seed_service.dart';
import '../memory/agent_memory_repository.dart';
import 'local_agent_transaction_summary.dart';

final class AgentCategoryReference {
  const AgentCategoryReference({
    required this.id,
    required this.name,
    this.icon,
  });

  final int id;
  final String name;
  final String? icon;

  Map<String, Object?> toToolData() => {
        'id': id,
        'name': name,
        if (icon != null && icon!.trim().isNotEmpty) 'icon': icon,
      };
}

final class AgentAccountReference {
  const AgentAccountReference({
    required this.id,
    required this.name,
    required this.currency,
  });

  final int id;
  final String name;
  final String currency;

  Map<String, Object?> toToolData() => {
        'id': id,
        'name': name,
        'currency': currency,
      };
}

final class AgentTagReference {
  const AgentTagReference({required this.id, required this.name});

  final int id;
  final String name;

  Map<String, Object?> toToolData() => {'id': id, 'name': name};
}

final class AgentTransactionSummary {
  const AgentTransactionSummary({
    required this.id,
    required this.ledgerId,
    required this.type,
    required this.amount,
    required this.happenedAt,
    required this.note,
    this.ledgerAmount,
    this.currency = 'CNY',
    this.ledgerCurrency = 'CNY',
    this.category,
    this.account,
    this.toAccount,
    this.tags = const [],
    this.excludeFromStats = false,
    this.excludeFromBudget = false,
  });

  final int id;
  final int ledgerId;
  final String type;
  final double amount;
  final DateTime happenedAt;
  final String? note;
  final double? ledgerAmount;
  final String currency;
  final String ledgerCurrency;
  final AgentCategoryReference? category;
  final AgentAccountReference? account;
  final AgentAccountReference? toAccount;
  final List<AgentTagReference> tags;
  final bool excludeFromStats;
  final bool excludeFromBudget;

  Map<String, Object?> toToolData() => {
        'id': id,
        'ledgerId': ledgerId,
        'type': type,
        'amount': amount,
        'ledgerAmount': ledgerAmount ?? amount,
        'currency': currency,
        'ledgerCurrency': ledgerCurrency,
        'category': category?.toToolData(),
        'account': account?.toToolData(),
        'toAccount': toAccount?.toToolData(),
        'tags': tags.map((tag) => tag.toToolData()).toList(),
        'excludeFromStats': excludeFromStats,
        'excludeFromBudget': excludeFromBudget,
        'happenedAt': happenedAt.toIso8601String(),
        'note': _clip(note, 160),
      };
}

final class AgentBudgetUsageSummary {
  const AgentBudgetUsageSummary({
    required this.used,
    required this.budget,
    required this.remaining,
    required this.rate,
    required this.status,
  });

  final double used;
  final double budget;
  final double remaining;
  final double rate;
  final String status;

  Map<String, Object?> toToolData() => {
        'used': used,
        'budget': budget,
        'remaining': remaining,
        'rate': rate,
        'status': status,
      };
}

final class AgentCategoryBudgetSummary {
  const AgentCategoryBudgetSummary({
    required this.budgetId,
    required this.category,
    required this.usage,
  });

  final int budgetId;
  final AgentCategoryReference category;
  final AgentBudgetUsageSummary usage;

  Map<String, Object?> toToolData() => {
        'budgetId': budgetId,
        'category': category.toToolData(),
        'usage': usage.toToolData(),
      };
}

/// 账本清单条目。两个用途：注入上下文让模型知道本机有哪几本、各自本位币是什么，
/// 以及校验模型传来的 ledgerIds 是否真实存在（不存在的必须剔除，不能拿去查库）。
final class AgentLedgerSummary {
  const AgentLedgerSummary({
    required this.id,
    required this.name,
    required this.currency,
  });

  final int id;
  final String name;
  final String currency;

  Map<String, Object?> toToolData() => {
        'id': id,
        'name': name,
        'currency': currency,
      };
}

final class AgentBudgetSummary {
  const AgentBudgetSummary({
    required this.daysRemaining,
    required this.dailyAvailable,
    this.currency = 'CNY',
    this.ledgerName,
    this.total,
    this.categoryBudgets = const [],
  });

  final int daysRemaining;
  final double dailyAvailable;
  final String currency;

  /// 跨账本查询时标明这份预算属于哪一本；单账本时为 null，输出保持原样。
  final String? ledgerName;
  final AgentBudgetUsageSummary? total;
  final List<AgentCategoryBudgetSummary> categoryBudgets;

  Map<String, Object?> toToolData() => {
        if (ledgerName != null) 'ledgerName': ledgerName,
        'currency': currency,
        'daysRemaining': daysRemaining,
        'dailyAvailable': dailyAvailable,
        'total': total?.toToolData(),
        'categoryBudgets': categoryBudgets
            .map((categoryBudget) => categoryBudget.toToolData())
            .toList(),
      };
}

final class AgentRecurringTransactionSummary {
  const AgentRecurringTransactionSummary({
    required this.type,
    required this.amount,
    required this.frequency,
    required this.interval,
    this.id,
    this.currency = 'CNY',
    this.category,
    this.account,
    this.toAccount,
    this.dayOfMonth,
    this.dayOfWeek,
    this.monthOfYear,
    this.startDate,
    this.endDate,
    this.lastGeneratedDate,
    this.note,
    this.ledgerName,
  });

  final int? id;
  final String type;
  final double amount;
  final String currency;
  final AgentCategoryReference? category;
  final AgentAccountReference? account;
  final AgentAccountReference? toAccount;
  final String frequency;
  final int interval;
  final int? dayOfMonth;
  final int? dayOfWeek;
  final int? monthOfYear;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? lastGeneratedDate;
  final String? note;

  /// 跨账本查询时标明这条周期记账属于哪一本；单账本时为 null。
  final String? ledgerName;

  Map<String, Object?> toToolData() => {
        'id': id,
        'type': type,
        'amount': amount,
        'currency': currency,
        if (ledgerName != null) 'ledgerName': ledgerName,
        'category': category?.toToolData(),
        'account': account?.toToolData(),
        'toAccount': toAccount?.toToolData(),
        'frequency': frequency,
        'interval': interval,
        'dayOfMonth': dayOfMonth,
        'dayOfWeek': dayOfWeek,
        'monthOfYear': monthOfYear,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'lastGeneratedDate': lastGeneratedDate?.toIso8601String(),
        'note': note == null || note!.trim().isEmpty ? null : _clip(note, 120),
      };
}

final class AgentRecordToolResult {
  const AgentRecordToolResult({
    required this.success,
    this.transactionIds = const [],
    this.bills = const [],
    this.transactions = const [],
    this.unconvertedCurrencies = const [],
  });

  final bool success;
  final List<int> transactionIds;

  /// UI 卡片继续使用已保存的 BillInfo 快照，模型只接收 [transactions] 的
  /// 最终落库数据，避免把 AI 解析阶段的猜测当成事实。
  final List<Map<String, Object?>> bills;
  final List<AgentTransactionSummary> transactions;
  final List<String> unconvertedCurrencies;

  Map<String, Object?> toToolData() => {
        'success': success,
        'transactionIds': transactionIds,
        'transactions': transactions
            .map((transaction) => transaction.toToolData())
            .toList(),
        'unconvertedCurrencies': unconvertedCurrencies,
      };
}

/// Narrow app-facing port so tools can be tested without a full repository
/// mock and cannot access any cloud data path.
abstract interface class LocalAgentToolGateway {
  /// [ledgerIds] 是本次查询覆盖的账本。只读工具默认只含当前账本，模型可按需带上
  /// 清单里的其他账本；实现方必须剔除不存在的 id，不能直接拿去查库。
  Future<List<AgentTransactionSummary>> queryTransactions({
    required List<int> ledgerIds,
    required DateTime start,
    required DateTime end,
  });
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
  });
  Future<List<AgentBudgetSummary>> getBudgetStatus(List<int> ledgerIds);
  Future<String> getLedgerCurrency(int ledgerId);

  /// 应用主币种。跨账本统计时金额取的是交易的 native_amount（记账时折算到主币种），
  /// 所以多本一起汇总时标的必须是它，而不是其中某一个账本的本位币。
  Future<String> getBaseCurrency();

  /// 本机全部账本清单，用于注入上下文与校验 ledgerIds。
  Future<List<AgentLedgerSummary>> getLedgerCatalog();
  Future<List<AgentRecurringTransactionSummary>> getRecurringTransactions(
    List<int> ledgerIds,
  );
  Future<AgentRecordToolResult> recordTransaction({
    required int ledgerId,
    required String text,
  });
  Future<int> saveExplicitMemory({
    required int? ledgerId,
    required String content,
  });
  Future<bool> forgetMemory({
    required int ledgerId,
    required int memoryId,
  });
}

/// Production local gateway. It uses the same [AiBookkeeper] path as the
/// legacy chat, preserving bills, undo metadata, statistics refresh and sync.
final class BeeCountLocalAgentToolGateway implements LocalAgentToolGateway {
  BeeCountLocalAgentToolGateway({
    required BaseRepository repository,
    required BeeDatabase database,
    required AiBookkeeper bookkeeper,
    required AgentMemoryRepository memoryRepository,
    required this.baseCurrency,
  })  : _repository = repository,
        _summaryDataSource = LocalAgentTransactionSummaryDataSource(database),
        _bookkeeper = bookkeeper,
        _memoryRepository = memoryRepository;

  final BaseRepository _repository;
  final LocalAgentTransactionSummaryDataSource _summaryDataSource;
  final AiBookkeeper _bookkeeper;
  final AgentMemoryRepository _memoryRepository;

  /// 应用主币种的读取回调。主币种存在 SharedPreferences 里、由 Riverpod 的
  /// baseCurrencyProvider 暴露，而 gateway 是不持有 ref 的纯类，所以由构造方注入。
  /// 跨账本统计的金额是 native_amount（折算到主币种），报告币种时必须用它，不能拿
  /// 其中某一个账本的本位币冒充。
  final String Function() baseCurrency;

  @override
  Future<List<AgentTransactionSummary>> queryTransactions({
    required List<int> ledgerIds,
    required DateTime start,
    required DateTime end,
  }) async {
    // 逐本查再合并，而不是把多个 id 塞进一条 IN 查询：每条明细的 currency 取的是
    // 它所在账本的本位币，分开查才能保持正确，跨账本时不会串币。
    final results = <AgentTransactionSummary>[];
    for (final ledgerId in ledgerIds) {
      final ledgerFuture = _repository.getLedgerById(ledgerId);
      final transactions = await _repository.getTransactionsWithCategoryInRange(
        ledgerId: ledgerId,
        start: start,
        end: end,
      );
      results.addAll(await _summarizeTransactions(
        transactions,
        ledger: await ledgerFuture,
      ));
    }
    return results;
  }

  @override
  Future<List<AgentLedgerSummary>> getLedgerCatalog() async {
    final ledgers = await _repository.getAllLedgers();
    return [
      for (final ledger in ledgers)
        AgentLedgerSummary(
          id: ledger.id,
          name: ledger.name,
          currency: _ledgerCurrency(ledger),
        ),
    ];
  }

  @override
  Future<String> getBaseCurrency() async =>
      _currencyOr(baseCurrency(), fallback: 'CNY');

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
  }) =>
      _summaryDataSource.summarizeTransactions(
        ledgerIds: ledgerIds,
        baseCurrency: baseCurrency(),
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

  @override
  Future<List<AgentBudgetSummary>> getBudgetStatus(
    List<int> ledgerIds,
  ) async {
    // 预算是按账本设的，跨本只能逐本取。单本查询不标注归属，输出与改动前保持一致；
    // 只有同时查多本时才需要 ledgerName 区分来源。
    final labelLedgers = ledgerIds.length > 1;
    final items = <AgentBudgetSummary>[];
    for (final ledgerId in ledgerIds) {
      final ledger = await _repository.getLedgerById(ledgerId);
      final overview =
          await _repository.getBudgetOverview(ledgerId, DateTime.now());
      final total = overview.totalBudget;
      items.add(AgentBudgetSummary(
        ledgerName: labelLedgers ? ledger?.name : null,
        daysRemaining: overview.daysRemaining,
        dailyAvailable: overview.dailyAvailable,
        currency: _ledgerCurrency(ledger),
        total: total == null ? null : _budgetUsage(total),
        categoryBudgets: overview.categoryBudgets
            .map(
              (categoryBudget) => AgentCategoryBudgetSummary(
                budgetId: categoryBudget.budgetId,
                category: AgentCategoryReference(
                  id: categoryBudget.categoryId,
                  name: categoryBudget.categoryName,
                  icon: categoryBudget.categoryIcon,
                ),
                usage: _budgetUsage(categoryBudget.usage),
              ),
            )
            .toList(),
      ));
    }
    return items;
  }

  @override
  Future<String> getLedgerCurrency(int ledgerId) async =>
      _ledgerCurrency(await _repository.getLedgerById(ledgerId));

  @override
  Future<List<AgentRecurringTransactionSummary>> getRecurringTransactions(
    List<int> ledgerIds,
  ) async {
    final items = <AgentRecurringTransactionSummary>[];
    // 与预算一致：单本不标注归属，跨本才带 ledgerName。
    final labelLedgers = ledgerIds.length > 1;
    for (final ledgerId in ledgerIds) {
      items.addAll(
        await _recurringForLedger(ledgerId, labelLedgers: labelLedgers),
      );
    }
    return items;
  }

  Future<List<AgentRecurringTransactionSummary>> _recurringForLedger(
    int ledgerId, {
    required bool labelLedgers,
  }) async {
    final ledgerFuture = _repository.getLedgerById(ledgerId);
    final categoriesFuture = _repository.getAllCategoriesIncludingShared();
    final rows = await _repository.getEnabledRecurringTransactions(ledgerId);
    final accountIds = {
      for (final row in rows) ...[
        if (row.accountId != null) row.accountId!,
        if (row.toAccountId != null) row.toAccountId!,
      ],
    };
    final accountsFuture = _repository.getAccountsByIds(accountIds.toList());
    final ledger = await ledgerFuture;
    final ledgerCurrency = _ledgerCurrency(ledger);
    final categoriesById = {
      for (final category in await categoriesFuture) category.id: category,
    };
    final accountsById = {
      for (final account in await accountsFuture) account.id: account,
    };
    return rows.map(
      (row) {
        final account =
            row.accountId == null ? null : accountsById[row.accountId!];
        return AgentRecurringTransactionSummary(
          id: row.id,
          type: row.type,
          amount: row.amount,
          currency: _currencyOr(
            row.currencyCode,
            fallback: account?.currency ?? ledgerCurrency,
          ),
          category: _categoryReference(
            row.categoryId == null ? null : categoriesById[row.categoryId!],
          ),
          account: _accountReference(account, fallbackCurrency: ledgerCurrency),
          toAccount: _accountReference(
            row.toAccountId == null ? null : accountsById[row.toAccountId!],
            fallbackCurrency: ledgerCurrency,
          ),
          frequency: row.frequency,
          interval: row.interval,
          dayOfMonth: row.dayOfMonth,
          dayOfWeek: row.dayOfWeek,
          monthOfYear: row.monthOfYear,
          startDate: row.startDate,
          endDate: row.endDate,
          lastGeneratedDate: row.lastGeneratedDate,
          note: row.note,
          ledgerName: labelLedgers ? ledger?.name : null,
        );
      },
    ).toList();
  }

  @override
  Future<AgentRecordToolResult> recordTransaction({
    required int ledgerId,
    required String text,
  }) async {
    final result = await _bookkeeper.fromText(
      text: text,
      ledgerId: ledgerId,
      billingTypes: [TagSeedService.billingTypeAi],
    );
    final transactions = result.success
        ? await _summarizeTransactionsByIds(ledgerId, result.transactionIds)
        : const <AgentTransactionSummary>[];
    return AgentRecordToolResult(
      success: result.success,
      transactionIds: result.transactionIds,
      bills: result.savedBills
          .map((bill) => Map<String, Object?>.from(bill.toJson()))
          .toList(),
      transactions: transactions,
      unconvertedCurrencies: result.unconvertedCurrencies,
    );
  }

  Future<List<AgentTransactionSummary>> _summarizeTransactionsByIds(
    int ledgerId,
    List<int> transactionIds,
  ) async {
    if (transactionIds.isEmpty) return const [];
    final ledgerFuture = _repository.getLedgerById(ledgerId);
    final rows = await _repository.getTransactionsWithCategoryByIds(
      ledgerId: ledgerId,
      transactionIds: transactionIds,
    );
    final summaries =
        await _summarizeTransactions(rows, ledger: await ledgerFuture);
    final summaryById = {for (final summary in summaries) summary.id: summary};
    return [
      for (final transactionId in transactionIds)
        if (summaryById[transactionId] case final summary?) summary,
    ];
  }

  Future<List<AgentTransactionSummary>> _summarizeTransactions(
    List<
            ({
              Transaction t,
              Category? category,
              Account? account,
              Account? toAccount,
            })>
        rows, {
    required Ledger? ledger,
  }) async {
    final tagsByTransaction = await _repository.getTagsForTransactions(
      rows.map((row) => row.t.id).toList(),
    );
    final ledgerCurrency = _ledgerCurrency(ledger);
    return rows
        .map(
          (row) => _agentTransactionSummary(
            transaction: row.t,
            category: row.category,
            account: row.account,
            toAccount: row.toAccount,
            tags: tagsByTransaction[row.t.id] ?? const [],
            ledgerCurrency: ledgerCurrency,
          ),
        )
        .toList();
  }

  @override
  Future<int> saveExplicitMemory({
    required int? ledgerId,
    required String content,
  }) =>
      _memoryRepository
          .saveExplicit(
            AgentMemoryDraft(
              ledgerId: ledgerId,
              kind: 'explicit',
              content: content,
            ),
          )
          .then((memory) => memory.id);

  @override
  Future<bool> forgetMemory({
    required int ledgerId,
    required int memoryId,
  }) =>
      _memoryRepository.forget(memoryId, ledgerId: ledgerId);
}

String _ledgerCurrency(Ledger? ledger) {
  final currency = ledger?.currency.trim().toUpperCase();
  return currency == null || currency.isEmpty ? 'CNY' : currency;
}

AgentBudgetUsageSummary _budgetUsage(BudgetUsage usage) =>
    AgentBudgetUsageSummary(
      used: usage.used,
      budget: usage.budget,
      remaining: usage.remaining,
      rate: usage.rate,
      status: usage.status,
    );

AgentTransactionSummary _agentTransactionSummary({
  required Transaction transaction,
  required Category? category,
  required Account? account,
  required Account? toAccount,
  required List<Tag> tags,
  required String ledgerCurrency,
}) {
  final currency = _currencyOr(
    transaction.currencyCode,
    fallback: account?.currency ?? ledgerCurrency,
  );
  final tagReferences = tags
      .map((tag) => AgentTagReference(id: tag.id, name: tag.name))
      .toList()
    ..sort((left, right) => left.name.compareTo(right.name));
  return AgentTransactionSummary(
    id: transaction.id,
    ledgerId: transaction.ledgerId,
    type: transaction.type,
    amount: transaction.amount,
    ledgerAmount: transaction.nativeAmount ?? transaction.amount,
    currency: currency,
    ledgerCurrency: ledgerCurrency,
    category: category == null
        ? null
        : AgentCategoryReference(
            id: category.id,
            name: category.name,
            icon: category.icon,
          ),
    account: _accountReference(account, fallbackCurrency: ledgerCurrency),
    toAccount: _accountReference(toAccount, fallbackCurrency: ledgerCurrency),
    tags: tagReferences,
    excludeFromStats: transaction.excludeFromStats,
    excludeFromBudget: transaction.excludeFromBudget,
    happenedAt: transaction.happenedAt,
    note: transaction.note,
  );
}

AgentAccountReference? _accountReference(
  Account? account, {
  required String fallbackCurrency,
}) =>
    account == null
        ? null
        : AgentAccountReference(
            id: account.id,
            name: account.name,
            currency: _currencyOr(account.currency, fallback: fallbackCurrency),
          );

AgentCategoryReference? _categoryReference(Category? category) =>
    category == null
        ? null
        : AgentCategoryReference(
            id: category.id,
            name: category.name,
            icon: category.icon,
          );

String _currencyOr(String? value, {required String fallback}) {
  final normalized = value?.trim().toUpperCase();
  return normalized == null || normalized.isEmpty ? fallback : normalized;
}

/// Builds the P0 allowlisted tools for exactly one foreground ledger scope.
final class LocalAgentTools {
  LocalAgentTools({required this.scope, required this.gateway});

  static const _maximumRows = 20;
  static const _maximumRecurringTransactions = 20;

  /// 单次查询允许覆盖的账本数上限，防止模型构造超长 IN 列表把查询放大。
  static const _maximumLedgers = 20;

  final AgentScope scope;
  final LocalAgentToolGateway gateway;
  final Map<String, AgentRecordToolResult> _recordResults = {};
  (DateTime, DateTime)? _lastSummaryRange;

  AgentRecordToolResult? recordResultFor(AgentToolCall call) =>
      _recordResults[call.id];

  Map<String, AgentTool> build() {
    final tools = <String, AgentTool>{
      'query_transactions': _CallbackTool(
        'query_transactions',
        _queryTransactions,
      ),
      'get_transaction_summary': _CallbackTool(
        'get_transaction_summary',
        _transactionSummary,
      ),
      'get_budget_status': _CallbackTool('get_budget_status', _budgetStatus),
      'get_recurring_transactions': _CallbackTool(
        'get_recurring_transactions',
        _recurringTransactions,
      ),
      'record_transaction_from_text': _CallbackTool(
        'record_transaction_from_text',
        _recordTransaction,
      ),
      'save_explicit_memory': _CallbackTool(
        'save_explicit_memory',
        _saveMemory,
      ),
      'forget_memory': _CallbackTool('forget_memory', _forgetMemory),
    };
    return Map.unmodifiable(tools);
  }

  Future<Map<String, Object?>> _queryTransactions(AgentToolCall call) async {
    final range = _rangeFor(call);
    final ledgerIds = await _ledgerIdsFor(call);
    final transactions = await gateway.queryTransactions(
      ledgerIds: ledgerIds,
      start: range.$1,
      end: range.$2,
    );
    final allowed = ledgerIds.toSet();
    final items = transactions
        .where((transaction) => allowed.contains(transaction.ledgerId))
        .take(_maximumRows)
        .map((transaction) => transaction.toToolData())
        .toList();
    return {'items': items};
  }

  Future<Map<String, Object?>> _transactionSummary(
    AgentToolCall call,
  ) async {
    final range = _rangeFor(call, previous: _lastSummaryRange);
    _lastSummaryRange = range;
    final types = _summaryTypesFor(call);
    return gateway.summarizeTransactions(
      ledgerIds: await _ledgerIdsFor(call),
      start: range.$1,
      end: range.$2,
      types: types,
      groupBy: _summaryGroupByFor(call),
      categoryLevel: _summaryCategoryLevelFor(call),
      categoryIds: _intListArgument(call, 'categoryIds'),
      categoryNames: _stringListArgument(call, 'categoryNames'),
      tagIds: _intListArgument(call, 'tagIds'),
      tagNames: _stringListArgument(call, 'tagNames'),
      accountIds: _intListArgument(call, 'accountIds'),
      accountNames: _stringListArgument(call, 'accountNames'),
      includeExcludedFromStats:
          call.arguments['includeExcludedFromStats'] == true,
      groupLimit: _summaryGroupLimitFor(call),
    );
  }

  Future<Map<String, Object?>> _budgetStatus(AgentToolCall call) async {
    final rows = await gateway.getBudgetStatus(await _ledgerIdsFor(call));
    return {
      'items': rows.map((summary) => summary.toToolData()).toList(),
    };
  }

  Future<Map<String, Object?>> _recurringTransactions(
    AgentToolCall call,
  ) async {
    final rows = await gateway
        .getRecurringTransactions(await _ledgerIdsFor(call));
    return {
      'items': rows
          .take(_maximumRecurringTransactions)
          .map((row) => row.toToolData())
          .toList(),
    };
  }

  Future<Map<String, Object?>> _recordTransaction(AgentToolCall call) async {
    final text = call.arguments['sourceText'];
    if (text is! String || text.isEmpty || scope.ledgerId == null) {
      return const {'success': false};
    }
    final target = await _recordTargetLedger(call);
    if (target.error != null) {
      return {'success': false, 'error': target.error};
    }
    final result =
        await gateway.recordTransaction(ledgerId: target.id!, text: text);
    if (call.id.isNotEmpty) _recordResults[call.id] = result;
    return result.toToolData();
  }

  /// 这笔账记进哪一本：模型只给账本**名称**，这里对着真实清单解析成 id。
  ///
  /// 不收 id 是因为名称才是用户嘴上说的东西；让模型自己挑 id，等于让它决定钱进哪本账。
  /// 解析不出来一律拒绝，绝不悄悄退回当前账本 —— 那样记错了账面上一切正常，只能事后
  /// 翻出来改。账本名在本机不唯一（建账本没做重名校验），所以重名也必须停下来问用户。
  Future<({int? id, String? error})> _recordTargetLedger(
      AgentToolCall call) async {
    final raw = call.arguments['ledgerName'];
    if (raw is! String || raw.trim().isEmpty) {
      return (id: _ledgerId, error: null);
    }
    final wanted = raw.trim();
    final catalog = await gateway.getLedgerCatalog();
    final matched =
        catalog.where((ledger) => ledger.name.trim() == wanted).toList();
    if (matched.length == 1) return (id: matched.single.id, error: null);
    if (matched.isEmpty) {
      final names = catalog.map((ledger) => ledger.name).join('、');
      return (
        id: null,
        error: '本机没有名为「$wanted」的账本，可选账本：$names。'
            '请不要改记到别的账本，先向用户确认。',
      );
    }
    return (
      id: null,
      error: '有 ${matched.length} 个账本都叫「$wanted」，无法确定记进哪一本，'
          '请先向用户确认。',
    );
  }

  Future<Map<String, Object?>> _saveMemory(AgentToolCall call) async {
    final content = call.arguments['content'];
    if (content is! String || content.trim().isEmpty) {
      return const {'saved': false};
    }
    final memoryId = await gateway.saveExplicitMemory(
        ledgerId: scope.ledgerId, content: content.trim());
    return {'saved': true, 'memoryId': memoryId};
  }

  Future<Map<String, Object?>> _forgetMemory(AgentToolCall call) async {
    final memoryId = call.arguments['memoryId'];
    if (memoryId is! int) return const {'forgotten': false};
    final forgotten = await gateway.forgetMemory(
      ledgerId: _ledgerId,
      memoryId: memoryId,
    );
    return {'forgotten': forgotten};
  }

  int get _ledgerId => scope.ledgerId!;

  /// 本次查询覆盖哪些账本。不传就是当前账本，与改动前的行为完全一致；模型要跨账本
  /// 时，从上下文里的账本清单取 id 传进来。
  ///
  /// 必须拿真实清单过一遍再放行：模型给的 id 不校验就进 SQL，等于允许它探测本机存在
  /// 哪些不存在的账本、或构造超长 IN 列表放大查询。清单里没有的一律丢弃；全被丢弃时
  /// 退回当前账本，保证每次调用都有确定且安全的范围。数量同时掐上限。
  Future<List<int>> _ledgerIdsFor(AgentToolCall call) async {
    final raw = call.arguments['ledgerIds'];
    if (raw is! List) return [_ledgerId];
    final requested =
        raw.whereType<num>().map((value) => value.toInt()).toSet();
    if (requested.isEmpty) return [_ledgerId];
    final known = (await gateway.getLedgerCatalog()).map((l) => l.id).toSet();
    final allowed = requested
        .intersection(known)
        .take(_maximumLedgers)
        .toList();
    return allowed.isEmpty ? [_ledgerId] : allowed;
  }

  (DateTime, DateTime) _rangeFor(
    AgentToolCall call, {
    (DateTime, DateTime)? previous,
  }) {
    // A model often needs one aggregate for totals and another for a named
    // category/tag/account. Reusing the last explicit summary interval keeps
    // those calls on the same slice instead of silently falling back to the
    // rolling 30-day default.
    final now = DateTime.now();
    final start = DateTime.tryParse(call.arguments['start'] as String? ?? '') ??
        previous?.$1 ??
        now.subtract(const Duration(days: 30));
    final end = DateTime.tryParse(call.arguments['end'] as String? ?? '') ??
        previous?.$2 ??
        now;
    return (start, end.isBefore(start) ? now : end);
  }

  Set<String> _summaryTypesFor(AgentToolCall call) {
    const supported = {'income', 'expense', 'transfer'};
    final raw = call.arguments['types'];
    final requested = raw is List
        ? raw.whereType<String>().where(supported.contains).toSet()
        : const <String>{};
    return requested.isEmpty ? supported : requested;
  }

  String _summaryGroupByFor(AgentToolCall call) {
    const supported = {
      'none',
      'ledger',
      'category',
      'tag',
      'account',
      'day',
      'week',
      'month',
      'year',
    };
    final raw = call.arguments['groupBy'];
    return raw is String && supported.contains(raw) ? raw : 'none';
  }

  String _summaryCategoryLevelFor(AgentToolCall call) =>
      call.arguments['categoryLevel'] == 'top' ? 'top' : 'leaf';

  List<int> _intListArgument(AgentToolCall call, String key) {
    final raw = call.arguments[key];
    if (raw is! List) return const [];
    return raw.whereType<int>().toSet().toList()..sort();
  }

  List<String> _stringListArgument(AgentToolCall call, String key) {
    final raw = call.arguments[key];
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  int _summaryGroupLimitFor(AgentToolCall call) {
    final raw = call.arguments['groupLimit'];
    return raw is int ? raw.clamp(1, 50) : 20;
  }
}

final class _CallbackTool implements AgentTool {
  const _CallbackTool(this.name, this._callback);

  @override
  final String name;
  final Future<Map<String, Object?>> Function(AgentToolCall) _callback;

  @override
  Future<Map<String, Object?>> execute(AgentToolCall call) => _callback(call);
}

String? _clip(String? value, int maximumLength) {
  if (value == null || value.length <= maximumLength) return value;
  return '${value.substring(0, maximumLength)}…';
}
