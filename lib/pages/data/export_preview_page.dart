import 'dart:math' as math;

import 'package:beecount/data/repositories/base_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:beecount/styles/tokens.dart';
import 'package:beecount/widgets/ui/ui.dart';
import 'package:flutter/material.dart';

/// 导出前的预览页：用**真实数据**完整展示即将写进文件的内容。
///
/// 刻意复用 TransactionExportService.buildSheet，所以预览里的列顺序、币种兜底、分类
/// 拆级、转账拆账户跟最终文件是同一份代码算出来的 —— 预览自己再拼一遍，两边迟早会
/// 不一致。
///
/// 只接 [asExcel] 而不是 ExportFormat，是为了不反向 import 导出页形成环依赖。
class ExportPreviewPage extends StatefulWidget {
  const ExportPreviewPage({
    super.key,
    required this.repository,
    required this.ledgerIds,
    required this.asExcel,
    required this.columns,
  });

  final BaseRepository repository;
  final List<int> ledgerIds;
  final bool asExcel;
  final Set<ExportColumn> columns;

  @override
  State<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

class _ExportPreviewPageState extends State<ExportPreviewPage> {
  List<LedgerExportSheet>? _sheets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    final service = TransactionExportService(
      repository: widget.repository,
      l10n: l10n,
      context: context,
    );
    // 多账本时 CSV 靠「账本」列区分，Excel 靠 sheet 区分，与落盘侧同一判断。
    final multiLedger = widget.ledgerIds.length > 1;
    try {
      final sheets = <LedgerExportSheet>[];
      for (final id in widget.ledgerIds) {
        sheets.add(await service.buildSheet(
          id,
          includeLedgerColumn: multiLedger && !widget.asExcel,
          padTimeCell: !widget.asExcel,
          columns: widget.columns,
        ));
      }
      if (!mounted) return;
      setState(() => _sheets = sheets);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sheets = _sheets;

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(title: l10n.exportPreviewTitle, showBack: true),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : sheets == null
                    ? const Center(child: CircularProgressIndicator())
                    : _PreviewBody(sheets: sheets, asExcel: widget.asExcel),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      sheets == null ? null : () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.save_alt_outlined),
                  label: Text(l10n.exportPreviewConfirm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.sheets, required this.asExcel});

  final List<LedgerExportSheet> sheets;
  final bool asExcel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalAll =
        sheets.fold<int>(0, (sum, sheet) => sum + sheet.dataRowCount);

    // CSV 落盘是「第一份提供表头，其余只追加数据行」，预览必须照同样规则合并，
    // 否则用户看到的行数和文件里的不是一回事。
    final tables = asExcel
        ? [for (final s in sheets) (title: s.ledgerName, rows: s.rows)]
        : [
            (
              title: l10n.exportFormatCsv,
              rows: _mergeCsv(sheets),
            )
          ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  asExcel
                      ? l10n.exportFormatExcelHint
                      : l10n.exportFormatCsvHint,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: BeeTokens.textSecondary(context)),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.exportPreviewRowCount(totalAll),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: BeeTokens.textSecondary(context)),
              ),
            ],
          ),
        ),
        // 多账本 Excel 是多个 sheet，用 Tab 分开看；一次只渲染当前那张表，
        // 免得几个大账本同时挂在树上。
        if (tables.length > 1)
          Expanded(
            child: DefaultTabController(
              length: tables.length,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [for (final t in tables) Tab(text: t.title)],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final t in tables) _LazyTable(rows: t.rows)
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(child: _LazyTable(rows: tables.first.rows)),
      ],
    );
  }

  List<List<String>> _mergeCsv(List<LedgerExportSheet> sheets) {
    final rows = <List<String>>[];
    for (final sheet in sheets) {
      rows.addAll(rows.isEmpty ? sheet.rows : sheet.rows.skip(1));
    }
    return rows;
  }
}

/// 全量表格：表头固定，数据行用 ListView.builder 懒加载。
///
/// 不用 DataTable 是因为它会把所有行一次性构建成 widget，几千笔账本直接卡死。
class _LazyTable extends StatelessWidget {
  const _LazyTable({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || rows.first.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).exportPreviewEmptyLedger,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: BeeTokens.textSecondary(context)),
        ),
      );
    }

    final header = rows.first;
    final widths = _columnWidths(header, rows);
    final borderColor = BeeTokens.border(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: _Row(
              cells: header,
              widths: widths,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: BeeTokens.textPrimary(context)),
              borderColor: borderColor,
            ),
          ),
          Expanded(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length - 1,
              separatorBuilder: (_, __) =>
                  Divider(height: 0.5, thickness: 0.5, color: borderColor),
              itemBuilder: (context, index) => _Row(
                cells: rows[index + 1],
                widths: widths,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: BeeTokens.textPrimary(context)),
                borderColor: borderColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列宽按该列最长内容定，夹在 90~260 之间。按表头文字或列索引猜宽度在多语言下
  /// 会错，勾选改变列集合时也会错。
  List<double> _columnWidths(List<String> header, List<List<String>> rows) {
    final widths = List<double>.filled(header.length, 90);
    for (final row in rows) {
      for (var i = 0; i < header.length && i < row.length; i++) {
        final needed = row[i].trim().length * 15.0 + 28;
        if (needed > widths[i]) widths[i] = math.min(260.0, needed);
      }
    }
    return widths;
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    required this.widths,
    required this.style,
    required this.borderColor,
  });

  final List<String> cells;
  final List<double> widths;
  final TextStyle? style;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < widths.length; i++)
          Container(
            width: widths[i],
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: Text(
              i < cells.length ? cells[i].trim() : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
      ],
    );
  }
}
