// 导出页「账本三态按钮 + 列全选/取消 + 汇总列区」的 UI 行为。
//
// 锁三件事：默认全选所有账本（旧版只勾当前账本，用户要的就是全导）；右侧按钮按
// 点选→全部→取消循环且回点选时清掉手动集合；汇总列区只在 Excel+多账本时出现，
// 默认勾「账本/笔数/支出」，账本列不给取消。

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/data/export_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/services/export/transaction_export_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int currentId;
  late List<Ledger> rows;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    currentId = await repo.createLedger(name: '日常');
    await repo.createLedger(name: '国宇');
    await repo.createLedger(name: '华恒远');
    rows = await repo.getAllLedgers();
  });

  tearDown(() async => db.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerIdProvider.overrideWith((ref) => currentId),
        ledgersStreamProvider.overrideWith((ref) => Stream.value(rows)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const ExportPage(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Iterable<bool> ledgerChipStates(WidgetTester tester) => rows.map((l) =>
      tester
          .widget<FilterChip>(find.ancestor(
              of: find.text(l.name), matching: find.byType(FilterChip)))
          .selected);

  Finder modeButton() => find.byKey(const ValueKey('export-ledger-mode'));

  testWidgets('默认全选所有账本，按钮从「点选」起循环', (tester) async {
    await pumpPage(tester);

    expect(ledgerChipStates(tester).every((s) => s), isTrue,
        reason: '没点过时默认全导，而不是旧版只勾当前账本');
    expect(find.descendant(of: modeButton(), matching: find.text('点选')),
        findsOneWidget);
  });

  testWidgets('取消态清空全部勾选，再点回「点选」恢复默认全选', (tester) async {
    await pumpPage(tester);

    await tester.tap(modeButton()); // 点选 → 全部
    await tester.pump();
    expect(find.descendant(of: modeButton(), matching: find.text('全部账本')),
        findsOneWidget);

    await tester.tap(modeButton()); // 全部 → 取消
    await tester.pump();
    expect(ledgerChipStates(tester).every((s) => !s), isTrue);

    await tester.tap(modeButton()); // 取消 → 点选（手动集合清掉=默认全选）
    await tester.pump();
    expect(ledgerChipStates(tester).every((s) => s), isTrue);
    expect(find.descendant(of: modeButton(), matching: find.text('点选')),
        findsOneWidget);
  });

  testWidgets('导出列按钮：全选到只剩金额来回切', (tester) async {
    await pumpPage(tester);

    final button = find.byKey(const ValueKey('export-column-mode'));
    expect(find.descendant(of: button, matching: find.text('全选列')),
        findsOneWidget, reason: '默认只勾三列，按钮该给「全选」动作');

    await tester.tap(button);
    await tester.pump();
    expect(find.descendant(of: button, matching: find.text('取消全选')),
        findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    // 取消全选后只剩必选的金额列（只看带 export-column-* key 的交易列方块）。
    final selected = tester
        .widgetList<FilterChip>(find.byType(FilterChip))
        .where((c) =>
            (c.key as ValueKey<String>?)?.value.startsWith('export-column-') ??
            false)
        .where((c) => c.selected)
        .toList();
    expect(selected.length, 1, reason: '只剩金额列必选');
  });

  testWidgets('汇总列区默认勾「账本/笔数/支出」，账本列不给取消', (tester) async {
    await pumpPage(tester);

    // Excel + 多账本（默认全选）→ 汇总列区可见。
    expect(find.byKey(const ValueKey('export-summary-columns-wrap')),
        findsOneWidget);

    FilterChip summaryChip(SummaryColumn c) => tester.widget<FilterChip>(
        find.byKey(ValueKey('export-summary-column-${c.name}')));
    expect(summaryChip(SummaryColumn.ledger).selected, isTrue);
    expect(summaryChip(SummaryColumn.count).selected, isTrue);
    expect(summaryChip(SummaryColumn.expense).selected, isTrue);
    expect(summaryChip(SummaryColumn.income).selected, isFalse);
    expect(summaryChip(SummaryColumn.balance).selected, isFalse);

    // 必选列 onSelected=null：点了也不会变。
    await tester.tap(find.byKey(
        const ValueKey('export-summary-column-ledger')));
    await tester.pump();
    expect(summaryChip(SummaryColumn.ledger).selected, isTrue);
  });
}
