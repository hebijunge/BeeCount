import 'package:beecount/services/ai/clipboard_bill_prefilter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('剪贴板预筛：该送模型的', () {
    test('口语金额（数字 + 单位）', () {
      expect(clipboardTextLooksLikeBill('昨天打车35块'), isTrue);
      expect(clipboardTextLooksLikeBill('午饭 -23.50'), isTrue);
      expect(clipboardTextLooksLikeBill('¥128.00'), isTrue);
      expect(clipboardTextLooksLikeBill('支付成功 66.00元'), isTrue);
    });

    test('账单惯用词 + 数字', () {
      expect(clipboardTextLooksLikeBill('订单金额 890'), isTrue);
      expect(clipboardTextLooksLikeBill('合计 1200'), isTrue);
      expect(clipboardTextLooksLikeBill('Total 45.9'), isTrue);
      expect(clipboardTextLooksLikeBill('收到工资 12000'), isTrue);
    });

    test('外币码', () {
      expect(clipboardTextLooksLikeBill('paid 30 USD'), isTrue);
    });
  });

  group('剪贴板预筛：该静默剔除的', () {
    test('纯文字无金额线索', () {
      expect(clipboardTextLooksLikeBill('今晚一起吃饭怎么样'), isFalse);
      expect(clipboardTextLooksLikeBill('会议纪要：下周确认排期'), isFalse);
    });

    test('链接（哪怕里面带数字）', () {
      expect(
        clipboardTextLooksLikeBill('https://example.com/item/12345'),
        isFalse,
      );
      expect(clipboardTextLooksLikeBill('www.taobao.com'), isFalse);
    });

    test('纯编号 / 验证码', () {
      expect(clipboardTextLooksLikeBill('823746289364'), isFalse);
      expect(clipboardTextLooksLikeBill('SF1234567890123'), isFalse);
    });

    test('空与超短', () {
      expect(clipboardTextLooksLikeBill(null), isFalse);
      expect(clipboardTextLooksLikeBill(''), isFalse);
      expect(clipboardTextLooksLikeBill('   '), isFalse);
      expect(clipboardTextLooksLikeBill('3'), isFalse);
    });

    test('超长文本（整篇粘贴）', () {
      final long = '金额 100 元。' * 400;
      expect(long.length, greaterThan(kClipboardBillMaxLength));
      expect(clipboardTextLooksLikeBill(long), isFalse);
    });
  });

  test('喂模型的文本会去空白并截断到上限', () {
    final long = 'a1元' * 1000;
    final out = clipboardTextForExtraction('  $long  ');
    expect(out.length, kClipboardBillPromptMaxLength);
    expect(clipboardTextForExtraction('  打车35块  '), '打车35块');
  });
}
