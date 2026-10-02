// 剪贴板记账预览弹窗：入账前可改金额 / 类型 / 分类 / 备注 / 账本，确认才落库。
//
// 锁死三件事：① 落库按 `amount.abs()` + `type` 的既有形态（BillCreationService
// 就是这么存的，弹窗里"支出为负"只是 BillInfo 层的约定）；② 换收/支类型会把分类清空
// （否则界面上显示的分类会被落库兜底成「其他」，是假象）；③ 金额非法的那笔不参与
// 入账，而不是把整批卡死。

import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/ai/clipboard_bill_preview_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: '日常');
    await repo.createCategory(name: '交通', kind: 'expense');
    await repo.createCategory(name: '工资', kind: 'income');
  });

  tearDown(() async => db.close());

  List<BillInfo> twoBills() => [
        BillInfo(
          amount: -35,
          time: DateTime(2026, 10, 1, 9, 0),
          note: '打车',
          category: '交通',
          type: BillType.expense,
          ledgerId: ledgerId,
        ),
        BillInfo(
          amount: 12000,
          time: DateTime(2026, 10, 1, 10, 0),
          note: '九月工资',
          category: '工资',
          type: BillType.income,
          ledgerId: ledgerId,
        ),
      ];

  /// 用一个宿主按钮打开弹窗，这样能拿到 pop 返回值，也不会去 pop 根路由。
  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<BillInfo> bills,
    required void Function(int?) onResult,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final saved = await ClipboardBillPreviewDialog.show(
                    context,
                    bills: bills,
                    sourceText: '昨天打车35块，今天发工资12000',
                    defaultLedgerId: ledgerId,
                  );
                  onResult(saved);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('两笔渲染两张卡，金额取绝对值预填、备注沿用', (tester) async {
    int? result;
    await pumpDialog(tester, bills: twoBills(), onResult: (v) => result = v);

    expect(find.text('剪贴板里有可记的账'), findsOneWidget);
    expect(find.text('35.00'), findsOneWidget);
    expect(find.text('12000.00'), findsOneWidget);
    expect(find.text('打车'), findsOneWidget);
    expect(find.text('九月工资'), findsOneWidget);
    // 两笔都可入账
    expect(find.text('入账 2 笔'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('类型是下拉，且排在分类上一行', (tester) async {
    int? result;
    await pumpDialog(tester, bills: twoBills(), onResult: (v) => result = v);

    // 收起状态下只显示当前值，不铺开三个选项
    expect(find.byIcon(Icons.arrow_drop_down), findsNWidgets(2));
    expect(find.widgetWithText(DropdownMenuItem, '转账'), findsNothing);

    // 遮罩调浅过：默认 black54（alpha 137）会被感知成"闪黑屏"
    final barriers = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .where((b) => b.color == Colors.black.withValues(alpha: 0.24));
    expect(barriers, hasLength(1));

    final typeY = tester.getRect(find.text('类型').first).center.dy;
    final categoryY = tester.getRect(find.text('分类').first).center.dy;
    final ledgerY = tester.getRect(find.text('账本').first).center.dy;
    expect(typeY, lessThan(categoryY));
    expect(categoryY, lessThan(ledgerY));
  });

  /// 落库路径上 `LoggerService` 会排一个 2s 防抖 Timer，不推进时钟的话
  /// widget 测试结束时会因 pending timer 报 `!timersPending`。
  Future<void> drainLoggerTimer(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 3));

  testWidgets('确认入账：按 abs 金额 + type 落库，改过的备注一起落库', (tester) async {
    int? result;
    await pumpDialog(tester, bills: twoBills(), onResult: (v) => result = v);

    await tester.enterText(find.widgetWithText(TextField, '备注').first, '打车去车站');
    await tester.pump();

    await tester.tap(find.text('入账 2 笔'));
    await tester.pumpAndSettle();
    await drainLoggerTimer(tester);

    expect(result, 2);
    final txs = await repo.getTransactionsByLedger(ledgerId);
    expect(txs.length, 2);
    final byNote = {for (final t in txs) t.note: t};
    expect(byNote['打车去车站']!.amount, 35);
    expect(byNote['打车去车站']!.type, 'expense');
    expect(byNote['九月工资']!.amount, 12000);
    expect(byNote['九月工资']!.type, 'income');
  });

  testWidgets('改收/支类型会把分类清空，不留会被兜底成「其他」的假象', (tester) async {
    int? result;
    // 用单笔：两笔时另一笔收起态的下拉本身就显示「收入」，菜单项会被撞。
    await pumpDialog(
      tester,
      bills: [twoBills().first],
      onResult: (v) => result = v,
    );

    // 原本是支出、分类「交通」。类型是下拉，要先展开再选。
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();

    expect(find.text('交通'), findsNothing);
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('金额清空只挡住那一笔，另一笔照常入账', (tester) async {
    int? result;
    await pumpDialog(tester, bills: twoBills(), onResult: (v) => result = v);

    await tester.enterText(find.widgetWithText(TextField, '金额').first, '');
    // 输入框保持焦点时光标闪烁的 Timer 不会停，pumpAndSettle 会一直等下去。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(find.text('金额不合法'), findsOneWidget);
    expect(find.text('入账 1 笔'), findsOneWidget);

    await tester.tap(find.text('入账 1 笔'));
    await tester.pumpAndSettle();
    await drainLoggerTimer(tester);

    expect(result, 1);
    final txs = await repo.getTransactionsByLedger(ledgerId);
    expect(txs.length, 1);
    expect(txs.single.amount, 12000);
  });

  testWidgets('删掉一笔后只剩一张卡，入账数随之减少', (tester) async {
    int? result;
    await pumpDialog(tester, bills: twoBills(), onResult: (v) => result = v);

    expect(find.byIcon(Icons.close_outlined), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close_outlined).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_outlined), findsNothing);
    expect(find.text('12000.00'), findsOneWidget);
    expect(find.text('入账 1 笔'), findsOneWidget);
  });

  testWidgets('取消返回 null，不落库', (tester) async {
    int? result = -1;
    await pumpDialog(tester, bills: twoBills(), onResult: (v) => result = v);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(await repo.getTransactionsByLedger(ledgerId), isEmpty);
  });
}
