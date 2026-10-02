// 剪贴板预筛的契约：本地只挡"结构上不可能是账单"的，语义判定交给模型。
//
// 硬判据一条：没有数字就一定不是账。刻意不认「元/块/金额/¥」这类词汇线索 ——
// "给国宇买工具64" 这种"人 + 事 + 裸数字"是真实主用法，靠词表必漏，
// 而漏掉的后果（用户永远等不到提示、且无从排查）比多调一次模型严重。

import 'package:beecount/services/ai/clipboard_bill_prefilter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('该放行的（有数字，语义交给模型判）', () {
    test('口语裸数字 —— 用户实际报的用法', () {
      expect(clipboardTextLooksLikeBill('给国宇买工具64'), isTrue);
      expect(clipboardTextLooksLikeBill('国宇 工具 64'), isTrue);
      expect(clipboardTextLooksLikeBill('买钻头12块'), isTrue);
      expect(clipboardTextLooksLikeBill('午饭 -23.50'), isTrue);
      expect(clipboardTextLooksLikeBill('¥128.00'), isTrue);
    });

    test('英文与币种码', () {
      expect(clipboardTextLooksLikeBill('Taxi fare 35.50'), isTrue);
      expect(clipboardTextLooksLikeBill('paid 30 USD'), isTrue);
    });

    test('带数字的非账单文本也放行，由模型剔除', () {
      // 这些本地判不出来，放行是对的 —— 判语义是模型的活。
      expect(clipboardTextLooksLikeBill('订单号 1234567890'), isTrue);
      expect(clipboardTextLooksLikeBill('SF1234567890123'), isTrue);
      expect(clipboardTextLooksLikeBill('今晚8点吃饭'), isTrue);
    });
  });

  group('该静默剔除的（结构上不可能）', () {
    test('一个数字都没有', () {
      expect(clipboardTextLooksLikeBill('今晚一起吃饭怎么样'), isFalse);
      expect(clipboardTextLooksLikeBill('会议纪要：下周确认排期'), isFalse);
      expect(clipboardTextLooksLikeBill('地址：某路一二三号'), isFalse);
    });

    test('纯数字 / 纯编号（只有数字与分隔符）', () {
      expect(clipboardTextLooksLikeBill('823746289364'), isFalse);
      expect(clipboardTextLooksLikeBill('13812345678'), isFalse);
      expect(clipboardTextLooksLikeBill('2026-10-02'), isFalse);
      expect(clipboardTextLooksLikeBill('6222 0210 1234 5678'), isFalse);
    });

    test('链接', () {
      expect(clipboardTextLooksLikeBill('https://example.com/item/12345'), isFalse);
      expect(clipboardTextLooksLikeBill('www.taobao.com'), isFalse);
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
