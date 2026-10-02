/// 剪贴板文本进大模型之前的本地预筛。
///
/// 存在的理由：这个检测挂在「启动」和「每次切回前台」上，不做预筛就等于
/// 每次回到 app 都要烧一次模型调用。
///
/// 判据只有一条硬的：**账单一定有金额，金额一定有数字** —— 一个数字都没有的
/// 文本（聊天、文章、地址、代码注释）不可能是一笔账，本地就能断定。
/// 反过来"有数字"不代表是账单，但那一步交给模型（见
/// [PromptBuilder.billGuardForText]），本地不再猜。
///
/// 刻意**不**要求出现「元 / 块 / 金额 / ¥」这类线索：真实用法里"给国宇买工具64"
/// 这种"人 + 事 + 裸数字"最常见，靠词汇表去认必然漏，而漏掉的后果是用户
/// 明明复制了账单却永远等不到提示、且无从排查 —— 比多调用一次模型严重得多。
library;

/// 超过这个长度基本不可能是随手记一笔的账单，多半是整篇文章 / 日志 / 代码。
const int kClipboardBillMaxLength = 2000;

/// 真正喂给模型的文本上限。账单信息都在开头，截断既省 token 也防止
/// 超长粘贴把 prompt 撑爆。
const int kClipboardBillPromptMaxLength = 1200;

/// 短到这个程度不可能同时含金额与用途。
const int kClipboardBillMinLength = 2;

final RegExp _digit = RegExp(r'[0-9０-９]');

/// 整条只有数字与分隔符：电话、订单号、验证码、快递单号、日期。
final RegExp _numberOnly = RegExp(r'^[0-9０-９\s\-–—_/.,:，、#]+$');

/// 整条就是一个链接（含可选的尾部空白）。
final RegExp _bareLink =
    RegExp(r'^\s*(https?://|www\.)\S+\s*$', caseSensitive: false);

/// 这段剪贴板文本值不值得交给模型判一次。
bool clipboardTextLooksLikeBill(String? raw) {
  if (raw == null) return false;
  final text = raw.trim();
  if (text.length < kClipboardBillMinLength) return false;
  if (text.length > kClipboardBillMaxLength) return false;
  if (_bareLink.hasMatch(raw)) return false;
  if (!_digit.hasMatch(text)) return false;
  if (_numberOnly.hasMatch(text)) return false;
  return true;
}

/// 截断成适合喂模型的长度。
String clipboardTextForExtraction(String raw) {
  final text = raw.trim();
  if (text.length <= kClipboardBillPromptMaxLength) return text;
  return text.substring(0, kClipboardBillPromptMaxLength);
}
