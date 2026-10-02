import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 智能记账自动关联标签开关（默认开启）
final smartBillingAutoTagsProvider = StateProvider<bool>((ref) => true);

/// 智能记账自动添加附件开关（默认开启）
final smartBillingAutoAttachmentProvider = StateProvider<bool>((ref) => true);

/// 智能记账自动关联标签持久化初始化
final smartBillingAutoTagsInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('smartBillingAutoTags');
  if (saved != null) {
    ref.read(smartBillingAutoTagsProvider.notifier).state = saved;
  }
  ref.listen<bool>(smartBillingAutoTagsProvider, (prev, next) async {
    await prefs.setBool('smartBillingAutoTags', next);
  });
});

/// 智能记账自动添加附件持久化初始化
final smartBillingAutoAttachmentInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('smartBillingAutoAttachment');
  if (saved != null) {
    ref.read(smartBillingAutoAttachmentProvider.notifier).state = saved;
  }
  ref.listen<bool>(smartBillingAutoAttachmentProvider, (prev, next) async {
    await prefs.setBool('smartBillingAutoAttachment', next);
  });
});

/// 剪贴板记账开关。**默认关闭** —— 它会在每次启动/切回前台时静默读系统剪贴板
/// 并把内容交给大模型判断，属于"用户必须知道自己开了什么"的那类能力。
final clipboardBillEnabledProvider = StateProvider<bool>((ref) => false);

/// 剪贴板记账开关持久化初始化
final clipboardBillEnabledInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('clipboardBillEnabled');
  if (saved != null) {
    ref.read(clipboardBillEnabledProvider.notifier).state = saved;
  }
  ref.listen<bool>(clipboardBillEnabledProvider, (prev, next) async {
    await prefs.setBool('clipboardBillEnabled', next);
  });
});
