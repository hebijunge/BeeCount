/// 剪贴板文本进大模型之前的本地预筛。
///
/// 存在的理由：这个检测挂在「启动」和「每次切回前台」上，不做预筛就等于
/// 每次回到 app 都要烧一次模型调用。绝大多数剪贴板内容是聊天、链接、验证码、
/// 代码，本地一眼能判掉，剩下可疑的才交给模型定夺（见
/// [PromptBuilder.billGuardForText]）。
library;

/// 超过这个长度基本不可能是随手记一笔的账单，多半是整篇文章 / 日志 / 代码。
const int kClipboardBillMaxLength = 2000;

/// 真正喂给模型的文本上限。账单信息都在开头，截断既省 token 也防止
/// 超长粘贴把 prompt 撑爆。
const int kClipboardBillPromptMaxLength = 1200;

/// 短到这个程度不可能同时含金额与用途。
const int kClipboardBillMinLength = 2;

final RegExp _digit = RegExp(r'[0-9０-９]');

/// 金额线索：币种符号 / 口语单位 / ISO 码 / 账单惯用词 / 带小数的数额。
///
/// 词汇表刻意往宽里列：漏判的后果是"用户明明复制了账单却永远等不到提示"，
/// 而且他无从排查原因；多放行一条只是多花一次模型调用。撞到新的说法就往这里补。
final RegExp _moneySignal = RegExp(
  r'[¥￥$€£₩₹]'
  r'|[元块刀円]|美金|美元|人民币|港币|台币'
  r'|\b(CNY|USD|EUR|JPY|GBP|HKD|KRW|TWD|AUD|CAD|RMB)\b'
  r'|金额|总价|合计|小计|实付|实收|支付|付款|付费|收款|退款|转账|消费|花费|支出|收入|账单|结算|单价|价格|报价|扣款|扣费'
  r'|工资|薪水|薪资|报销|奖金|红包|补贴|提成|绩效|分红|到账|入账|充值|提现|结账|买单|扫码'
  r'|\b(total|amount|price|paid|pay|fee|cost|subtotal|charge|refund|salary|bonus|income)\b'
  r'|[0-9]+\.[0-9]{1,2}',
  caseSensitive: false,
);

/// 整条就是一个链接（含可选的尾部空白）。
final RegExp _bareLink = RegExp(r'^\s*(https?://|www\.)\S+\s*$', caseSensitive: false);

/// 这段剪贴板文本值不值得交给模型判一次。
///
/// 判定刻意做成"宁可放过、不要错杀"的宽松口径：漏判只是多花一次调用，
/// 错判会让用户明明复制了账单却永远等不到提示，而且他无从排查原因。
bool clipboardTextLooksLikeBill(String? raw) {
  if (raw == null) return false;
  final text = raw.trim();
  if (text.length < kClipboardBillMinLength) return false;
  if (text.length > kClipboardBillMaxLength) return false;
  if (_bareLink.hasMatch(raw)) return false;
  // 金额线索里的小数模式本身已含数字，但符号/词汇类线索不一定，所以分开判。
  return _digit.hasMatch(text) && _moneySignal.hasMatch(text);
}

/// 截断成适合喂模型的长度。
String clipboardTextForExtraction(String raw) {
  final text = raw.trim();
  if (text.length <= kClipboardBillPromptMaxLength) return text;
  return text.substring(0, kClipboardBillPromptMaxLength);
}
