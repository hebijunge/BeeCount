import 'package:flutter/widgets.dart';

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/category_utils.dart';

/// repo.transactionsWithCategoryAll 吐出的行结构。
typedef _TxRow = ({
  Transaction t,
  Category? category,
  Account? account,
  Account? toAccount,
});

/// 可勾选的导出列。**声明顺序就是文件里的列顺序**，沿用历史导出的排布，
/// 这样用户取消勾选只会让列变少，不会把剩下的列挪位。
enum ExportColumn {
  type,
  category,
  subCategory,
  amount,
  currency,
  account,
  fromAccount,
  toAccount,
  note,
  time,
  tags,
  attachments;

  /// 默认只勾「时间 / 备注 / 金额」三列。
  static const Set<ExportColumn> defaultSelected = {time, note, amount};

  /// 默认列顺序：把「时间」挪到「金额」前面，其余保持枚举相对顺序。
  /// 拖动排序 / 落盘顺序都以这份列表为基线（[defaultOrder] 可被用户重排覆盖）。
  static const List<ExportColumn> defaultOrder = [
    type,
    category,
    subCategory,
    time,
    amount,
    currency,
    account,
    fromAccount,
    toAccount,
    note,
    tags,
    attachments,
  ];

  /// 金额是账单的本体，缺了这份文件既没法看也没法回导，所以不给取消。
  bool get isRequired => this == ExportColumn.amount;

  String headerText(AppLocalizations l10n) => switch (this) {
        ExportColumn.type => l10n.exportCsvHeaderType,
        ExportColumn.category => l10n.exportCsvHeaderCategory,
        ExportColumn.subCategory => l10n.exportCsvHeaderSubCategory,
        ExportColumn.amount => l10n.exportCsvHeaderAmount,
        ExportColumn.currency => l10n.exportCsvHeaderCurrency,
        ExportColumn.account => l10n.exportCsvHeaderAccount,
        ExportColumn.fromAccount => l10n.exportCsvHeaderFromAccount,
        ExportColumn.toAccount => l10n.exportCsvHeaderToAccount,
        ExportColumn.note => l10n.exportCsvHeaderNote,
        ExportColumn.time => l10n.exportCsvHeaderTime,
        ExportColumn.tags => l10n.exportCsvHeaderTags,
        ExportColumn.attachments => l10n.exportCsvHeaderAttachments,
      };
}

extension ExportColumnSelection on Set<ExportColumn> {
  /// 本次实际输出的列：按枚举顺序取交集，并强制补上必选列。
  ///
  /// 补齐放在服务层而不是 UI 层，是为了让任何调用方（包括以后新增的入口）都造不出
  /// 一份没有金额列的文件；UI 只负责把必选列渲染成不可取消。
  List<ExportColumn> get resolved => [
        for (final column in ExportColumn.values)
          if (contains(column) || column.isRequired) column,
      ];

  /// 按调用方给的 [order] 出列：取「勾选列 ∪ 必选列」与 [order] 的交集并保留
  /// [order] 的先后 —— 让用户拖动排序后的顺序直接决定文件列序。
  ///
  /// [order] 漏掉的必选列（正常不会发生，因为 [order] 是全列排布）兜底追加到末尾，
  /// 保证任何重排都造不出缺金额的文件。
  List<ExportColumn> resolvedIn(List<ExportColumn> order) {
    final picked = <ExportColumn>[
      for (final column in order)
        if (contains(column) || column.isRequired) column,
    ];
    for (final column in ExportColumn.values) {
      if ((contains(column) || column.isRequired) && !picked.contains(column)) {
        picked.add(column);
      }
    }
    return picked;
  }
}

/// 单个账本的导出内容：[rows] 第 0 行是表头，其余是数据行。
///
/// [income] / [expense] 是该账本的收入与支出合计，供多账本汇总 sheet 直接取用。
class LedgerExportSheet {
  const LedgerExportSheet({
    required this.ledgerId,
    required this.ledgerName,
    required this.rows,
    this.income = 0,
    this.expense = 0,
  });

  final int ledgerId;
  final String ledgerName;
  final List<List<String>> rows;
  final double income;
  final double expense;

  int get dataRowCount => rows.isEmpty ? 0 : rows.length - 1;

  double get balance => income - expense;
}

/// 汇总 sheet 不对应任何账本，用这个哨兵 id 标注（sheet 名取「汇总」文案）。
const int summarySheetLedgerId = -1;

/// 把某个账本的交易摊成表格行。CSV 与 xlsx 两条落盘路径共用这一份取数逻辑，
/// 避免两种格式的列顺序、币种兜底、分类拆级规则各写一遍而漂移。
class TransactionExportService {
  TransactionExportService({
    required BaseRepository repository,
    required AppLocalizations l10n,
    required BuildContext context,
  })  : _repo = repository,
        _l10n = l10n,
        _context = context;

  final BaseRepository _repo;
  final AppLocalizations _l10n;
  final BuildContext _context;

  /// [includeLedgerColumn] 给多账本合并进单张表（CSV 没有 sheet）时加一列账本名。
  /// [padTimeCell] 保留 CSV 时代给 Excel 撑列宽加的前后空格；xlsx 有真列宽，不需要。
  /// [columns] 勾选要输出的列，必选列会被强制补齐。
  /// [columnOrder] 输出列的先后顺序（全列排布，通常来自 UI 的拖动排序）；不传则
  /// 回落 [ExportColumn] 枚举声明顺序。
  /// [startDate] / [endDate] 是「整日」语义：起=当天 00:00，止=当天 24:00（含整天）。
  /// 都为 null 时导全量，跟旧行为一致。
  Future<LedgerExportSheet> buildSheet(
    int ledgerId, {
    bool includeLedgerColumn = false,
    bool padTimeCell = true,
    Set<ExportColumn> columns = ExportColumn.defaultSelected,
    List<ExportColumn>? columnOrder,
    DateTime? startDate,
    DateTime? endDate,
    void Function(double progress)? onProgress,
  }) async {
    List<({Transaction t, Category? category, Account? account, Account? toAccount})>
        transactionsWithCategory;
    if (startDate == null && endDate == null) {
      transactionsWithCategory =
          await _repo.transactionsWithCategoryAll(ledgerId: ledgerId).first;
    } else {
      // 底层 InRange 的 end 是开区间：起=当天 00:00，止=次日 00:00（含止日整天）。
      // 只设了一侧时，另一侧用 1970/9999 两个哨兵撑开，行为等同「不限」。
      final start = startDate != null
          ? DateTime(startDate.year, startDate.month, startDate.day)
          : DateTime(1970, 1, 1);
      final end = endDate != null
          ? DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1))
          : DateTime(9999, 12, 31);
      transactionsWithCategory = await _repo.getTransactionsWithCategoryInRange(
        ledgerId: ledgerId,
        start: start,
        end: end,
      );
    }
    final total = transactionsWithCategory.length;

    final ledger = await _repo.getLedgerById(ledgerId);
    final ledgerName = ledger?.name ?? '';
    final ledgerBase =
        ((ledger?.currency.isNotEmpty ?? false) ? ledger!.currency : 'CNY')
            .toUpperCase();

    final pickedColumns = columnOrder != null
        ? columns.resolvedIn(columnOrder)
        : columns.resolved;
    final header = <String>[
      if (includeLedgerColumn) _l10n.exportCsvHeaderLedger,
      for (final column in pickedColumns) column.headerText(_l10n),
    ];

    final transactionIds = transactionsWithCategory.map((tx) => tx.t.id).toList();
    final tagsMap = await _repo.getTagsForTransactions(transactionIds);
    final attachmentsMap = await _repo.getAttachmentsForTransactions(transactionIds);

    final allAccounts = await _repo.getAllAccounts();
    final accountMap = {for (final acc in allAccounts) acc.id: acc};

    // 分类要连父级一起缓存，二级分类才能拆成「分类 / 二级分类」两列。
    final categoryMap = <int, Category>{};
    for (final kind in ['income', 'expense']) {
      for (final cat in await _repo.getTopLevelCategories(kind)) {
        categoryMap[cat.id] = cat;
        for (final sub in await _repo.getSubCategories(cat.id)) {
          categoryMap[sub.id] = sub;
        }
      }
    }

    final rows = <List<String>>[header];
    for (var i = 0; i < transactionsWithCategory.length; i++) {
      final values = _columnValues(
        transactionsWithCategory[i],
        accountMap: accountMap,
        categoryMap: categoryMap,
        tagsMap: tagsMap,
        attachmentsMap: attachmentsMap,
        ledgerBase: ledgerBase,
        padTimeCell: padTimeCell,
      );
      rows.add([
        if (includeLedgerColumn) ledgerName,
        for (final column in pickedColumns) values[column]!,
      ]);
      if (i % 50 == 0) {
        onProgress?.call((i + 1) / (total == 0 ? 1 : total));
      }
    }
    onProgress?.call(1);

    // 收入/支出合计就地算，不再走 getLedgerStats：一是省一次全表查询，二是汇总 sheet
    // 必须和这份已摊开的行严格同源，两条路径各算各的迟早对不上账。
    // 取 nativeAmount（记账时按主币种折算的折叠值）而不是 t.amount —— 同一账本可以
    // 混记多币种，裸加原值等于把 CNY 和 JPY 直接相加。转账不计收支。
    var income = 0.0, expense = 0.0;
    for (final row in transactionsWithCategory) {
      final v = row.t.nativeAmount ?? row.t.amount;
      if (row.t.type == 'income') {
        income += v;
      } else if (row.t.type == 'expense') {
        expense += v;
      }
    }

    return LedgerExportSheet(
      ledgerId: ledgerId,
      ledgerName: ledgerName,
      rows: rows,
      income: income,
      expense: expense,
    );
  }

  /// 多账本导出的**第一张** sheet：逐本一行「账本 / 笔数 / 收入 / 支出 / 结余」。
  ///
  /// 数字全部取自传进来的 [ledgerSheets]（即各账本刚算完的那份），不二次查库。
  /// 金额是主币种折算后的 nativeAmount 合计，所以三个金额列的表头带上币种码，免得
  /// 跨币种账本被当成原币相加。
  ///
  /// 静态：它只需要文案和已算好的行，挂成实例方法会让人以为要一个 service 才能拼汇总。
  static LedgerExportSheet buildSummarySheet(
    AppLocalizations l10n,
    List<LedgerExportSheet> ledgerSheets, {
    required String currencyCode,
  }) {
    final suffix = '(${currencyCode.toUpperCase()})';
    return LedgerExportSheet(
      ledgerId: summarySheetLedgerId,
      ledgerName: l10n.exportSummarySheetName,
      rows: [
        [
          l10n.exportCsvHeaderLedger,
          l10n.exportSummaryColCount,
          '${l10n.exportSummaryColIncome}$suffix',
          '${l10n.exportSummaryColExpense}$suffix',
          '${l10n.exportSummaryColBalance}$suffix',
        ],
        for (final sheet in ledgerSheets)
          [
            sheet.ledgerName,
            sheet.dataRowCount.toString(),
            sheet.income.toStringAsFixed(2),
            sheet.expense.toStringAsFixed(2),
            sheet.balance.toStringAsFixed(2),
          ],
      ],
    );
  }

  /// 算出一行的**全部**列值，由调用方按勾选顺序取子集。
  ///
  /// 取值不跟勾选联动，是为了让勾与不勾都走同一条取数路径 —— 否则「取消某列」和
  /// 「该列取空值」会分成两套代码，币种兜底、转账拆账户这些易错点就要各写一遍。
  Map<ExportColumn, String> _columnValues(
    _TxRow txWithCat, {
    required Map<int, Account> accountMap,
    required Map<int, Category> categoryMap,
    required Map<int, List<Tag>> tagsMap,
    required Map<int, List<TransactionAttachment>> attachmentsMap,
    required String ledgerBase,
    required bool padTimeCell,
  }) {
    final t = txWithCat.t;
    final c = txWithCat.category;
    final a = t.accountId != null ? accountMap[t.accountId] : null;

    final timeStr = _formatTime(t.happenedAt, padTimeCell);

    String accountName;
    String fromAccountName;
    String toAccountName;
    String categoryName;
    String subCategoryName;

    if (t.type == 'transfer') {
      // 转账：账户列留空，改用转出 / 转入两列，且转账没有分类。
      accountName = '';
      fromAccountName = accountMap[t.accountId]?.name ?? '';
      toAccountName = accountMap[t.toAccountId]?.name ?? '';
      categoryName = '';
      subCategoryName = '';
    } else {
      accountName = a?.name ?? '';
      fromAccountName = '';
      toAccountName = '';
      if (c != null) {
        if (c.level == 2 && c.parentId != null) {
          categoryName =
              CategoryUtils.getDisplayName(categoryMap[c.parentId]?.name, _context);
          subCategoryName = CategoryUtils.getDisplayName(c.name, _context);
        } else {
          categoryName = CategoryUtils.getDisplayName(c.name, _context);
          subCategoryName = '';
        }
      } else {
        categoryName = '';
        subCategoryName = '';
      }
    }

    final tagsStr = (tagsMap[t.id] ?? []).map((tag) => tag.name).join(',');
    final attachmentsStr =
        (attachmentsMap[t.id] ?? []).map((f) => f.fileName).join(',');

    // 币种兜底与统计读取端同语义：交易自带 > 账户币种 > 账本本位币，
    // 保证导出文件自包含、回导不丢币种。
    final currencyStr = (t.currencyCode ??
            ((a?.currency.isNotEmpty ?? false) ? a!.currency : null) ??
            ledgerBase)
        .toUpperCase();

    return {
      ExportColumn.type: _typeName(t.type),
      ExportColumn.category: categoryName,
      ExportColumn.subCategory: subCategoryName,
      ExportColumn.amount: t.amount.toStringAsFixed(2),
      ExportColumn.currency: currencyStr,
      ExportColumn.account: accountName,
      ExportColumn.fromAccount: fromAccountName,
      ExportColumn.toAccount: toAccountName,
      ExportColumn.note: t.note ?? '',
      ExportColumn.time: timeStr,
      ExportColumn.tags: tagsStr,
      ExportColumn.attachments: attachmentsStr,
    };
  }

  String _formatTime(DateTime happenedAt, bool pad) {
    final local = happenedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final text = '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    // CSV 时代靠前后空格撑开 Excel 列宽，历史行为保持不变。
    return pad ? '  $text  ' : text;
  }

  String _typeName(String type) {
    switch (type) {
      case 'income':
        return _l10n.exportTypeIncome;
      case 'expense':
        return _l10n.exportTypeExpense;
      case 'transfer':
        return _l10n.exportTypeTransfer;
      default:
        return type;
    }
  }
}
