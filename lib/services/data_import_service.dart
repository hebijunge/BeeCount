import 'package:drift/drift.dart' as d;
import '../data/db.dart';
import '../data/repositories/base_repository.dart';
import '../data/repositories/transaction_repository.dart' show BatchAttachmentData;
import 'currency/rate_math.dart';
import 'export/xlsx_workbook_writer.dart' show safeSheetName;
import 'system/logger_service.dart';

/// 统一的数据导入服务
///
/// 用于CSV导入和云端恢复，确保两者使用相同的导入逻辑

// --- 导入数据模型 ---

/// 导入账户数据
class ImportAccount {
  final String name;
  final String? type;
  final String? currency;
  final double? initialBalance;

  const ImportAccount({
    required this.name,
    this.type,
    this.currency,
    this.initialBalance,
  });
}

/// 导入分类数据
class ImportCategory {
  final String name;
  final String kind; // 'income' or 'expense'
  final int level; // 1 or 2
  final int sortOrder; // 排序顺序
  final String? icon;
  final String? parentName; // 二级分类的父分类名称
  final String? iconType; // 图标类型: material / custom / community
  final String? customIconPath; // 自定义图标路径
  final String? communityIconId; // 社区图标ID

  const ImportCategory({
    required this.name,
    required this.kind,
    this.level = 1,
    this.sortOrder = 0,
    this.icon,
    this.parentName,
    this.iconType,
    this.customIconPath,
    this.communityIconId,
  });
}

/// 导入标签数据
class ImportTag {
  final String name;
  final String? color;

  const ImportTag({
    required this.name,
    this.color,
  });
}

/// 导入附件数据
class ImportAttachment {
  final String fileName;
  final String? originalName;
  final int? fileSize;
  final int? width;
  final int? height;
  final int sortOrder;
  final String? cloudFileId;
  final String? cloudSha256;

  const ImportAttachment({
    required this.fileName,
    this.originalName,
    this.fileSize,
    this.width,
    this.height,
    this.sortOrder = 0,
    this.cloudFileId,
    this.cloudSha256,
  });
}

/// 导入交易数据
class ImportTransaction {
  final String type; // 'income', 'expense', 'transfer'
  final double amount;
  final String? categoryName;
  final String? categoryKind;
  final DateTime happenedAt;
  final String? note;
  final String? accountName; // 普通账户（收入/支出）
  final String? fromAccountName; // 转出账户（转账）
  final String? toAccountName; // 转入账户（转账）
  final List<String>? tagNames; // 标签名称列表
  final int? categoryId; // 预解析的分类ID（优先于categoryName）
  final List<ImportAttachment>? attachments; // 附件元数据列表
  final String? syncId; // 跨设备同步唯一标识
  /// v30 多币种:CSV 币种列(反馈10)。null → 账户币种/账本本位币兜底。
  final String? currencyCode;
  /// 多账本导入：该行原本属于哪个账本。来源是导出 CSV 的「账本」列或 xlsx 的 sheet 名。
  /// 为 null 时沿用调用方传入的目标账本，即旧的单账本行为。
  final String? ledgerName;

  const ImportTransaction({
    required this.type,
    required this.amount,
    this.currencyCode,
    this.categoryName,
    this.categoryKind,
    required this.happenedAt,
    this.note,
    this.accountName,
    this.fromAccountName,
    this.toAccountName,
    this.tagNames,
    this.categoryId,
    this.attachments,
    this.syncId,
    this.ledgerName,
  });
}

/// 统一的导入数据格式
class ImportData {
  final List<ImportAccount> accounts;
  final List<ImportCategory> categories;
  final List<ImportTag> tags;
  final List<ImportTransaction> transactions;

  /// 账本名称（可选，用于更新账本信息）
  final String? ledgerName;
  /// 货币（可选，用于更新账本信息）
  final String? currency;

  const ImportData({
    this.accounts = const [],
    this.categories = const [],
    this.tags = const [],
    this.transactions = const [],
    this.ledgerName,
    this.currency,
  });
}

/// 导入结果
class ImportResult {
  final int inserted;
  final int failed;

  const ImportResult({
    required this.inserted,
    required this.failed,
  });
}

// --- 数据导入服务 ---

/// 通用数据导入服务
///
/// 提供统一的导入逻辑，支持：
/// - 账户创建（全局按名称去重）
/// - 分类创建（先一级后二级）
/// - 标签创建
/// - 交易插入（批量写入）
/// - 标签关联
class DataImportService {
  /// 按账本名找到目标账本，找不到就新建一个，返回其 id。
  ///
  /// 匹配同时接受「账本原名」和「sheet 安全化名」：xlsx 的 sheet 名是 safeSheetName
  /// 处理过的结果（截到 31 字符、非法字符换成空格、重名追加 `(2)`），只按原名比对会让
  /// 导入认不出自家导出的文件，从而静默多建一个重复账本。
  Future<int> ensureLedgerByName(
    BaseRepository repo,
    String name, {
    String currency = 'CNY',
  }) async {
    final wanted = name.trim();
    if (wanted.isEmpty) {
      throw ArgumentError('账本名不能为空');
    }
    final existing = findLedgerIn(await repo.getAllLedgers(), wanted);
    return existing ?? await repo.createLedger(name: wanted, currency: currency);
  }

  /// 账本名匹配规则本体，纯函数，供 [ensureLedgerByName] 和导入前的归属预览共用。
  static int? findLedgerIn(List<Ledger> ledgers, String name) {
    final wanted = name.trim();
    if (wanted.isEmpty) return null;
    final lower = wanted.toLowerCase();
    for (final ledger in ledgers) {
      final original = ledger.name.trim().toLowerCase();
      final sheetForm =
          safeSheetName(ledger.name, ledger.id).trim().toLowerCase();
      if (original == lower || sheetForm == lower) return ledger.id;
    }
    return null;
  }

  /// 导入数据到指定账本
  ///
  /// [repo] - 数据仓库
  /// [ledgerId] - 目标账本ID
  /// [data] - 导入数据
  /// [defaultCurrency] - 默认货币（用于创建账户）
  /// [onProgress] - 进度回调 (done, total)
  /// [recordChanges] - 默认 true,会调 repo.insertTransactionsBatch 时登记
  ///   changeTracker。FullPull 路径传 false,避免"从云端拉下来的数据又反向推
  ///   回去"。
  Future<ImportResult> importData(
    BaseRepository repo,
    int ledgerId,
    ImportData data, {
    String defaultCurrency = 'CNY',
    void Function(int done, int total)? onProgress,
    bool recordChanges = true,
  }) async {
    // 1. 账本本身不因导入文件而改名/改币种。
    //    旧实现在这里拿 data.ledgerName 直接 updateLedger，于是导入一个多账本文件会把
    //    用户当前所在的账本悄悄改成文件里那个名字，异常还被 catch (_) 吞掉无从察觉。
    //    现在多账本按每行的 ledgerName 分组落到各自账本，目标账本名称由用户自己决定；
    //    文件里的 currency 只用于给新建账户兜底币种（见下方 defaultCurrency）。

    // 2. 导入账户
    final accountNameToId = await importAccounts(
      repo,
      data.accounts,
      defaultCurrency: data.currency ?? defaultCurrency,
    );

    // 3. 导入分类
    final categoryCache = await importCategories(repo, data.categories);

    // 4. 导入标签
    final tagNameToId = await importTags(repo, data.tags);

    // 5. 导入交易
    final result = await importTransactions(
      repo,
      ledgerId,
      data.transactions,
      accountNameToId: accountNameToId,
      categoryCache: categoryCache,
      tagNameToId: tagNameToId,
      onProgress: onProgress,
      recordChanges: recordChanges,
    );

    return result;
  }

  /// 导入账户(全局按名称去重)。public — sync_diff_service 也复用,避免维护两套。
  Future<Map<String, int>> importAccounts(
    BaseRepository repo,
    List<ImportAccount> accounts,
    {String defaultCurrency = 'CNY'}
  ) async {
    final accountNameToId = <String, int>{};

    if (accounts.isEmpty) return accountNameToId;
    logger.info('AccountImport', '开始导入账户: ${accounts.length} 个');
    final sw = Stopwatch()..start();
    int created = 0;

    try {
      final existingAccounts = await repo.getAllAccounts();
      for (final acc in existingAccounts) {
        accountNameToId[acc.name] = acc.id;
      }

      for (final acc in accounts) {
        if (!accountNameToId.containsKey(acc.name)) {
          final id = await repo.createAccount(
            ledgerId: 0, // 账户独立,不绑定账本
            name: acc.name,
            type: acc.type ?? 'cash',
            currency: acc.currency ?? defaultCurrency,
            initialBalance: acc.initialBalance ?? 0.0,
          );
          accountNameToId[acc.name] = id;
          created++;
        }
      }
      logger.info('AccountImport',
          '账户导入完成: 新增=$created 已存在=${accounts.length - created} 耗时=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      logger.error('AccountImport', '账户导入失败', e, st);
    }

    return accountNameToId;
  }

  /// 导入分类(先一级后二级)。public — sync_diff_service 复用。
  Future<Map<String, int>> importCategories(
    BaseRepository repo,
    List<ImportCategory> categories,
  ) async {
    // 返回给交易导入做「分类名 → id」反查。分类名只在父级作用域内唯一，所以同一个
    // kind|name 可能对应多行，取法统一为「一级优先」（与同步层 resolve 的规则一致）。
    final categoryCache = <String, int>{};
    if (categories.isEmpty) return categoryCache;
    logger.info('CategoryImport', '开始导入分类: ${categories.length} 个');
    final sw = Stopwatch()..start();
    int created = 0;

    try {
      // 获取所有现有分类。一级按 kind|name 索引；二级必须带上父级 id，否则同名的
      // 一级/二级互相遮蔽，导入时既漏建又挂错父级。
      final existingExpense = await repo.getTopLevelCategories('expense');
      final existingIncome = await repo.getTopLevelCategories('income');
      final existingTops = [...existingExpense, ...existingIncome];
      final existingTopKeyToId = <String, int>{
        for (final cat in existingTops) '${cat.kind}|${cat.name}': cat.id,
      };
      final existingSubKeyToId = <String, int>{};
      for (final cat in existingTops) {
        final subCats = await repo.getSubCategories(cat.id);
        for (final sub in subCats) {
          existingSubKeyToId['${sub.kind}|${cat.id}|${sub.name}'] = sub.id;
        }
      }
      // 二级解析父级只查这张「纯一级」表：混进二级的话，与父级同名的子分类会顶掉
      // 父级，后面的兄弟分类就被挂到「儿子」底下去了。
      final topLevelCache = <String, int>{...existingTopKeyToId};

      // 分离一级和二级分类
      final level1 = categories.where((c) => c.level == 1 || c.parentName == null).toList();
      final level2 = categories.where((c) => c.level == 2 && c.parentName != null).toList();

      // 导入一级分类
      for (final cat in level1) {
        final key = '${cat.kind}|${cat.name}';
        final existingId = existingTopKeyToId[key];
        if (existingId != null) {
          categoryCache[key] = existingId;
        } else {
          final id = await repo.createCategory(
            name: cat.name,
            kind: cat.kind,
            icon: cat.icon,
            sortOrder: cat.sortOrder,
          );
          categoryCache[key] = id;
          topLevelCache[key] = id;
          created++;

          // 如果有自定义图标信息，更新图标
          if (cat.iconType != null && cat.iconType != 'material') {
            await repo.updateCategoryIcon(
              id,
              iconType: cat.iconType!,
              icon: cat.icon,
              customIconPath: cat.customIconPath,
              communityIconId: cat.communityIconId,
            );
          }
        }
      }

      // 导入二级分类
      for (final cat in level2) {
        final key = '${cat.kind}|${cat.name}';
        final parentKey = '${cat.kind}|${cat.parentName}';
        final parentId = topLevelCache[parentKey];
        if (parentId == null) {
          logger.warning('CategoryImport',
              '找不到父分类「${cat.parentName}」，跳过二级分类: ${cat.name}');
          continue;
        }
        final scopedKey = '${cat.kind}|$parentId|${cat.name}';
        final existingId = existingSubKeyToId[scopedKey];
        if (existingId != null) {
          categoryCache.putIfAbsent(key, () => existingId);
        } else {
          final id = await repo.createSubCategory(
            parentId: parentId,
            name: cat.name,
            kind: cat.kind,
            icon: cat.icon,
            sortOrder: cat.sortOrder,
          );
          existingSubKeyToId[scopedKey] = id;
          categoryCache.putIfAbsent(key, () => id);
          created++;

          // 如果有自定义图标信息，更新图标
          if (cat.iconType != null && cat.iconType != 'material') {
            await repo.updateCategoryIcon(
              id,
              iconType: cat.iconType!,
              icon: cat.icon,
              customIconPath: cat.customIconPath,
              communityIconId: cat.communityIconId,
            );
          }
        }
      }
      logger.info('CategoryImport',
          '分类导入完成: 新增=$created 已存在=${categories.length - created} 耗时=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      logger.error('CategoryImport', '分类导入失败', e, st);
    }

    return categoryCache;
  }

  /// 导入标签。public — sync_diff_service 复用。
  Future<Map<String, int>> importTags(
    BaseRepository repo,
    List<ImportTag> tags,
  ) async {
    final tagNameToId = <String, int>{};

    if (tags.isEmpty) return tagNameToId;

    logger.info('TagImport', '开始导入标签: ${tags.length} 个');
    final sw = Stopwatch()..start();
    int created = 0;
    int updated = 0;

    try {
      final existingTags = await repo.getAllTags();
      final existingTagMap = <String, Tag>{};
      for (final tag in existingTags) {
        tagNameToId[tag.name] = tag.id;
        existingTagMap[tag.name] = tag;
      }

      // 单条 await 循环 — 标签量通常小(<100),没批量接口暂保持,但去掉 per-row
      // INFO 日志:N 个标签会打 3N 条 INFO,把 logger 队列冲爆,导致后续 import
      // 阶段的日志被淹没,用户感知"日志不全"。
      for (final tag in tags) {
        if (!tagNameToId.containsKey(tag.name)) {
          final id = await repo.createTag(name: tag.name, color: tag.color);
          tagNameToId[tag.name] = id;
          created++;
        } else if (tag.color != null) {
          final existingTag = existingTagMap[tag.name];
          if (existingTag != null && existingTag.color != tag.color) {
            await repo.updateTag(existingTag.id, color: tag.color);
            updated++;
          }
        }
      }
      logger.info('TagImport',
          '标签导入完成: 新增=$created 更新=$updated 耗时=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      logger.error('TagImport', '标签导入失败', e, st);
    }

    return tagNameToId;
  }

  /// 导入交易(统一 batch 路径,tag/attachment 跟 tx 一起 batch insert)
  ///
  /// **历史**:之前"有标签/附件"的 tx 走单条 await 路径,
  ///   `insertTransactionCompanion` → `updateTransactionTags` → `createAttachment`
  /// 各开自己的 BEGIN/COMMIT,N+1 + 嵌套事务双重放大,1 万条带标签数据要几十
  /// 分钟。
  ///
  /// **现在**:全部走 `insertTransactionsBatchWithRelations`,500 条 / 批,
  /// 一个 db.transaction 内 batch insert tx + tag + attachment + local_changes,
  /// 把 N 次 BEGIN/COMMIT/fsync 折叠成 1 次。
  ///
  /// public — sync_diff_service 复用。
  Future<ImportResult> importTransactions(
    BaseRepository repo,
    int ledgerId,
    List<ImportTransaction> transactions, {
    required Map<String, int> accountNameToId,
    required Map<String, int> categoryCache,
    required Map<String, int> tagNameToId,
    void Function(int done, int total)? onProgress,
    bool recordChanges = true,
  }) async {
    int inserted = 0;
    int failed = 0;
    int processed = 0;
    final total = transactions.length;
    logger.info('TxImport',
        '开始导入交易: $total 条 (recordChanges=$recordChanges)');

    // v30 交易级多币种(02 §六导入修补):批量预取本位币/账户币种/有效汇率,
    // 逐条填 currencyCode + nativeAmount,不再落 NULL(NULL 行 L11 检测
    // 需 join 兜底,且外币账户导入折算会静默 1:1)。
    final ledger = await repo.getLedgerById(ledgerId);
    final ledgerBase = ((ledger?.currency.isNotEmpty ?? false)
            ? ledger!.currency
            : 'CNY')
        .toUpperCase();
    final accountCurrencyById = <int, String>{
      for (final a in await repo.getAllAccounts())
        a.id: (a.currency.isNotEmpty ? a.currency : ledgerBase).toUpperCase(),
    };
    Map<String, EffectiveRate> importRates = const {};
    try {
      final autos = await repo.getLatestAutoRates(ledgerBase);
      final overrides = await repo.getOverrides(ledgerBase);
      importRates = mergeEffectiveRates(
        autoRates: [
          for (final r in autos)
            (quote: r.quoteCurrency, rate: r.rate, rateDate: r.rateDate)
        ],
        overrides: [
          for (final o in overrides) (quote: o.quoteCurrency, rate: o.rate)
        ],
      );
    } catch (e) {
      logger.warning('TxImport', '导入取汇率失败,外币交易将按 1:1 待 L11 捞回: $e');
    }
    final overallSw = Stopwatch()..start();

    const batchSize = 500;
    // 批次缓冲:tx 列表 + 按 batch 内 index 索引的关联数据
    final batchTx = <TransactionsCompanion>[];
    final batchTagsByIndex = <int, List<int>>{};
    final batchAttachmentsByIndex = <int, List<BatchAttachmentData>>{};

    final localCategoryCache = Map<String, int>.from(categoryCache);

    // 把当前缓冲 flush 到 repo。捕获异常时整批算 failed,继续下一批。
    Future<void> flush() async {
      if (batchTx.isEmpty) return;
      final size = batchTx.length;
      final batchSw = Stopwatch()..start();
      try {
        final ids = await repo.insertTransactionsBatchWithRelations(
          transactions: List.of(batchTx),
          tagIdsByIndex: Map.of(batchTagsByIndex),
          attachmentsByIndex: Map.of(batchAttachmentsByIndex),
          recordChanges: recordChanges,
        );
        inserted += ids.length;
        logger.info('TxImport',
            'flush 批次: size=$size 耗时=${batchSw.elapsedMilliseconds}ms 累计=${processed + size}/$total');
      } catch (e, st) {
        logger.error('TxImport', '批次 flush 失败,本批 $size 条算 failed', e, st);
        failed += size;
      }
      processed += size;
      batchTx.clear();
      batchTagsByIndex.clear();
      batchAttachmentsByIndex.clear();
      if (onProgress != null) onProgress(processed, total);
    }

    for (final tx in transactions) {
      // 解析分类ID
      int? categoryId;
      if (tx.categoryId != null) {
        categoryId = tx.categoryId;
      } else if (tx.categoryName != null && tx.categoryKind != null) {
        final key = '${tx.categoryKind}|${tx.categoryName}';
        categoryId = localCategoryCache[key];
        if (categoryId == null && tx.type != 'transfer') {
          try {
            categoryId = await repo.upsertCategory(
              name: tx.categoryName!,
              kind: tx.categoryKind!,
            );
            localCategoryCache[key] = categoryId;
          } catch (_) {}
        }
      }

      // 解析账户ID
      int? accountId;
      int? toAccountId;
      if (tx.type == 'transfer') {
        if (tx.fromAccountName != null) {
          accountId = accountNameToId[tx.fromAccountName];
          if (accountId == null) {
            failed++;
            processed++;
            continue;
          }
        }
        if (tx.toAccountName != null) {
          toAccountId = accountNameToId[tx.toAccountName];
          if (toAccountId == null) {
            failed++;
            processed++;
            continue;
          }
        }
      } else {
        if (tx.accountName != null) {
          accountId = accountNameToId[tx.accountName];
        }
      }

      // 解析标签ID — toSet().toList() 去重,因为底层 batch insert 不查重
      final tagIds = <int>[];
      if (tx.tagNames != null) {
        for (final tagName in tx.tagNames!) {
          var tagId = tagNameToId[tagName];
          if (tagId == null) {
            try {
              final existingTag = await repo.getTagByName(tagName);
              if (existingTag != null) {
                tagId = existingTag.id;
              } else {
                tagId = await repo.createTag(name: tagName);
              }
              tagNameToId[tagName] = tagId;
            } catch (_) {}
          }
          if (tagId != null) {
            tagIds.add(tagId);
          }
        }
      }
      final uniqueTagIds = tagIds.toSet().toList();

      // v30:交易币种 = CSV 币种列(显式,反馈10)?? 账户币种 ?? 本位币;
      // 折算快照同币种 = amount,外币按有效汇率,取不到 = amount(L11 可捞回)。
      final txCurrency = ((tx.currencyCode?.isNotEmpty ?? false)
              ? tx.currencyCode!
              : null) ??
          (accountId != null ? accountCurrencyById[accountId] : null) ??
          ledgerBase;
      final txNative = txCurrency == ledgerBase
          ? tx.amount
          : (computeNativeAmount(
                  amount: tx.amount,
                  accountCurrency: txCurrency,
                  ledgerBase: ledgerBase,
                  rates: importRates) ??
              tx.amount);

      // 构建交易记录
      final txCompanion = TransactionsCompanion.insert(
        ledgerId: ledgerId,
        type: tx.type,
        amount: tx.amount,
        categoryId: d.Value(tx.type == 'transfer' ? null : categoryId),
        accountId: d.Value(accountId),
        toAccountId: d.Value(toAccountId),
        happenedAt: d.Value(tx.happenedAt),
        note: d.Value(tx.note),
        syncId: d.Value(tx.syncId),
        currencyCode: d.Value(txCurrency),
        nativeAmount: d.Value(txNative),
      );

      final indexInBatch = batchTx.length;
      batchTx.add(txCompanion);
      if (uniqueTagIds.isNotEmpty) {
        batchTagsByIndex[indexInBatch] = uniqueTagIds;
      }
      if (tx.attachments != null && tx.attachments!.isNotEmpty) {
        batchAttachmentsByIndex[indexInBatch] = tx.attachments!
            .map((a) => BatchAttachmentData(
                  fileName: a.fileName,
                  originalName: a.originalName,
                  fileSize: a.fileSize,
                  width: a.width,
                  height: a.height,
                  sortOrder: a.sortOrder,
                  cloudFileId: a.cloudFileId,
                  cloudSha256: a.cloudSha256,
                ))
            .toList();
      }

      if (batchTx.length >= batchSize) {
        await flush();
      }
    }

    // 刷剩余
    await flush();

    logger.info('TxImport',
        '交易导入完成: 总数=$total 成功=$inserted 失败=$failed 总耗时=${overallSw.elapsedMilliseconds}ms');
    return ImportResult(inserted: inserted, failed: failed);
  }
}

/// 全局单例
final dataImportService = DataImportService();
