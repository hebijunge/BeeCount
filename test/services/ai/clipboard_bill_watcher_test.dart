// 剪贴板记账扫描的门控：什么情况下读剪贴板、什么情况下才惊动用户。
//
// 锁死四条：① 开关关着连剪贴板都不该读；② 本地预筛不过就不调模型；③ 模型判"不是
// 账单"（返回空）就静默，不弹窗；④ 同一份剪贴板内容在一个进程里只问一次。
//
// 弹窗渲染本身由 test/widgets/ai/clipboard_bill_preview_dialog_test.dart 覆盖，
// 这里注入探针，只验"该不该弹"。

import 'dart:io';

import 'package:beecount/ai/core/ai_extraction_context.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/providers/ai_chat_providers.dart';
import 'package:beecount/services/ai/clipboard_bill_watcher.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程的 fake engine，不打真模型。
class _FakeEngine implements AiExtractionEngine {
  _FakeEngine(this.bills);

  final List<BillInfo> bills;
  int textCalls = 0;

  @override
  Future<List<BillInfo>> extractFromText(
    String text,
    AiExtractionContext context, {
    String billGuard = '',
  }) async {
    textCalls++;
    return bills;
  }

  @override
  Future<List<BillInfo>> extractFromImage(
    File image,
    AiExtractionContext context, {
    String billGuard = '',
  }) async =>
      bills;

  @override
  Future<AudioExtractionResult> extractFromAudio(
    File audio,
    AiExtractionContext context,
  ) async =>
      const AudioExtractionResult();

  @override
  Future<String?> speechToText(File audio) async => null;
}

void main() {
  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;
  late _FakeEngine engine;

  String? clipboardText;
  var clipboardReads = 0;
  var presentedCalls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClipboardBillWatcher.clearHandledForTest();
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: '日常');
    clipboardText = null;
    clipboardReads = 0;
    presentedCalls = 0;
    engine = _FakeEngine(const []);
  });

  tearDown(() async => db.close());

  Future<int?> recordPresenter(
    BuildContext context,
    List<BillInfo> bills,
    String sourceText,
    int defaultLedgerId,
  ) async {
    presentedCalls++;
    return null;
  }

  late BuildContext hostContext;
  late WidgetRef hostRef;

  Future<void> pumpHost(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentLedgerIdProvider.overrideWith((ref) => ledgerId),
          clipboardBillEnabledProvider.overrideWith((ref) => enabled),
          aiExtractionEngineProvider.overrideWithValue(engine),
          appInitStateProvider.overrideWith((ref) => AppInitState.ready),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                hostRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 真机上 lifecycleState 就是 resumed；测试绑定默认是 null，不设会被门控直接挡掉。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  Future<void> scan(WidgetTester tester) async {
    // 扫描里要查 drift（AiExtractionContext.forLedger），testWidgets 的 fake-async
    // 区里 await 真实 IO 会死锁，必须放进 runAsync。
    await tester.runAsync(() async {
      await ClipboardBillWatcher(presenter: recordPresenter)
          .scan(context: hostContext, ref: hostRef);
      await tester.pump();
    });
  }

  /// 把 `Clipboard.getData` 桩成返回 [clipboardText]。
  void mockClipboard() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardReads++;
        return clipboardText == null
            ? null
            : <String, String>{'text': clipboardText!};
      }
      return null;
    });
  }

  final oneBill = [
    BillInfo(
      amount: -35,
      time: DateTime(2026, 10, 1),
      note: '打车',
      type: BillType.expense,
    ),
  ];

  testWidgets('开关关着：连剪贴板都不读', (tester) async {
    mockClipboard();
    clipboardText = '昨天打车35块';
    await pumpHost(tester, enabled: false);

    await scan(tester);

    expect(clipboardReads, 0);
    expect(engine.textCalls, 0);
    expect(presentedCalls, 0);
  });

  testWidgets('预筛不过（纯聊天文字）：不调模型、不弹窗', (tester) async {
    mockClipboard();
    clipboardText = '今晚一起吃饭怎么样，我请你';
    await pumpHost(tester);

    await scan(tester);

    expect(clipboardReads, 1);
    expect(engine.textCalls, 0);
    expect(presentedCalls, 0);
  });

  testWidgets('预筛过但模型判不是账单：静默不弹窗', (tester) async {
    mockClipboard();
    clipboardText = '订单金额 890';
    await pumpHost(tester);

    await scan(tester);

    expect(engine.textCalls, 1);
    expect(presentedCalls, 0);
  });

  testWidgets('预筛过 + 模型给出账单：弹预览', (tester) async {
    mockClipboard();
    clipboardText = '昨天打车35块';
    engine = _FakeEngine(oneBill);
    await pumpHost(tester);

    await scan(tester);

    expect(engine.textCalls, 1);
    expect(presentedCalls, 1);
  });

  testWidgets('同一份剪贴板内容只问一次', (tester) async {
    mockClipboard();
    clipboardText = '昨天打车35块';
    engine = _FakeEngine(oneBill);
    await pumpHost(tester);

    await scan(tester);
    expect(presentedCalls, 1);

    // 用户取消后又切了一次前台，内容没变
    await scan(tester);

    expect(engine.textCalls, 1, reason: '第二次应被内容指纹挡在模型之前');
    expect(presentedCalls, 1);
  });

  testWidgets('内容变了就会重新判', (tester) async {
    mockClipboard();
    clipboardText = '昨天打车35块';
    engine = _FakeEngine(oneBill);
    await pumpHost(tester);

    await scan(tester);
    clipboardText = '今天午饭 62 元';
    await scan(tester);

    expect(engine.textCalls, 2);
    expect(presentedCalls, 2);
  });
}
