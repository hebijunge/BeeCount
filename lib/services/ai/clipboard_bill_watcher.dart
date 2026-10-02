import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/core/ai_extraction_context.dart';
import '../../ai/core/bill_info.dart';
import '../../ai/core/prompt_builder.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/ai_chat_providers.dart';
import '../../widgets/ai/clipboard_bill_preview_dialog.dart';
import '../../widgets/ui/toast.dart';
import '../system/logger_service.dart';
import 'clipboard_bill_prefilter.dart';

/// 展示预览弹窗并等用户确认。返回值 = 成功入账笔数，`null` = 用户取消。
typedef ClipboardBillPresenter = Future<int?> Function(
  BuildContext context,
  List<BillInfo> bills,
  String sourceText,
  int defaultLedgerId,
);

/// 启动 / 切回前台时的剪贴板记账扫描。
///
/// 流程：本地预筛（[clipboardTextLooksLikeBill]）→ 交给模型判是不是账单
/// （带 [PromptBuilder.billGuardForText]，不是就返回空）→ 弹
/// [ClipboardBillPreviewDialog] 让用户改完确认才落库。
///
/// 两道"剔除"都是静默的：预筛没过、或模型说不是账单，都不提示、不打扰。
class ClipboardBillWatcher {
  static const String _tag = 'ClipboardBill';

  /// 本进程内已经问过或已经判掉的剪贴板内容指纹。同一份内容反复切前台只问一次；
  /// 冷启动清空后允许再问，因为"启动检测"本身就是用户要的行为。
  static final Set<String> _handled = <String>{};

  /// 清空去重记录。指纹是进程级的，测试之间需要隔离。
  @visibleForTesting
  static void clearHandledForTest() => _handled.clear();

  /// 弹窗展示可注入：真实弹窗会查 drift 拿账本名，在 widget 测试的 fake-async
  /// 环境里渲染会死锁；门控逻辑本身不需要真把弹窗画出来。
  ClipboardBillWatcher({ClipboardBillPresenter? presenter})
      : _present = presenter ?? _showPreviewDialog;

  final ClipboardBillPresenter _present;

  static Future<int?> _showPreviewDialog(
    BuildContext context,
    List<BillInfo> bills,
    String sourceText,
    int defaultLedgerId,
  ) =>
      ClipboardBillPreviewDialog.show(
        context,
        bills: bills,
        sourceText: sourceText,
        defaultLedgerId: defaultLedgerId,
      );

  bool _scanning = false;

  /// 扫一次剪贴板。不满足前置条件时直接返回，不抛异常。
  Future<void> scan({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    if (_scanning) return;
    if (!ref.read(clipboardBillEnabledProvider)) return;
    if (ref.read(appInitStateProvider) != AppInitState.ready) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    _scanning = true;
    try {
      final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!clipboardTextLooksLikeBill(raw)) return;
      final text = clipboardTextForExtraction(raw!);

      final fingerprint = _fingerprint(text);
      if (_handled.contains(fingerprint)) return;
      // 先占位再提取：提取要等网络，期间用户又切了一次前台会重复弹窗。
      _handled.add(fingerprint);

      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final extractionContext = await AiExtractionContext.forLedger(
        repository: repo,
        ledgerId: ledgerId,
      );
      final bills = await ref.read(aiExtractionEngineProvider).extractFromText(
            text,
            extractionContext,
            billGuard: PromptBuilder.billGuardForText,
          );
      if (bills.isEmpty) {
        logger.debug(_tag, '剪贴板内容不含账单信息，静默跳过');
        return;
      }
      if (!context.mounted) return;

      logger.info(_tag, '剪贴板识别出 ${bills.length} 笔，弹预览');
      final saved = await _present(context, bills, text, ledgerId);
      if (saved == null || saved <= 0 || !context.mounted) return;
      showToast(context, AppLocalizations.of(context).clipboardBillSaved(saved));
    } catch (e, st) {
      // 被动触发的功能，任何异常都不该把错误抛回 UI 主流程。
      logger.warning(_tag, '剪贴板记账扫描失败，忽略', e);
      logger.debug(_tag, '异常堆栈: $st');
    } finally {
      _scanning = false;
    }
  }

  /// 内容指纹。只用于"同一份剪贴板别问第二遍"，不要求密码学强度，
  /// 而且刻意不保存原文（剪贴板可能含敏感信息，不该长期驻留在内存里）。
  String _fingerprint(String text) =>
      '${text.length}-${Object.hashAll(text.codeUnits)}';
}
