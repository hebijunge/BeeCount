// 真 endpoint 走 app 自己的调用路径，证明内置预设不是只在探测脚本里能用。
//
//   ZHIPU_API_KEY=*** REQUESTY_API_KEY=*** DOTS_API_KEY=*** \
//     flutter test test/ai/providers/ai_provider_preset_live_test.dart
//
// 没给 key 的那家直接 skip，不会把 CI 变成要翻墙才绿的样式。
// 离线用例（ai_provider_presets_test.dart）只证明参数流转；这里补的是三件事：
// chat() 的分协议分支真能回正文、chatWithToolsStream() 的 SSE 解析真能拿到结构化
// tool_calls、vision() 的 base64 data URL 真能读出金额。
//
// key 只从环境变量读，不落盘、不进提交。

import 'dart:convert';
import 'dart:io';

import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_factory.dart';
import 'package:beecount/ai/providers/ai_provider_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _envByPreset = <String, String>{
  'zhipu_glm': 'ZHIPU_API_KEY',
  'requesty_free': 'REQUESTY_API_KEY',
  'xiaohongshu_dots': 'DOTS_API_KEY',
  'intern_discovery': 'INTERN_API_KEY',
  'kilo_free': 'KILO_API_KEY',
  'amd_radeon': 'AMD_API_KEY',
};

const _extractText = '今天上午在公司楼下全家便利店买咖啡和面包 32 元，'
    '下午给华恒远项目采购冲击钻和配件一共 1280 元，'
    '另外客户把上月的报销款 5000 元打到了我的工资卡。';

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'get_period_overview',
      'description': '查询指定时间区间的总收入、总支出和结余',
      'parameters': {
        'type': 'object',
        'properties': {
          'start': {'type': 'string', 'description': 'ISO 8601 起始日期'},
          'end': {'type': 'string', 'description': 'ISO 8601 结束日期'},
        },
        'required': ['start', 'end'],
      },
    },
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 绑定会装一层 HttpOverrides 让所有请求直接 400，真联网必须摘掉。
  HttpOverrides.global = null;

  for (final preset in kAiProviderPresets) {
    final apiKey =
        (Platform.environment[_envByPreset[preset.id] ?? ''] ?? '').trim();
    final label = preset.name;

    group('$label 真 endpoint', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        await _bind(preset, apiKey);
      });

      test('抽取得到三笔金额正确的账单 JSON', () async {
        if (apiKey.isEmpty) return markTestSkipped('未给 key');
        final reply = await AIProviderFactory.chat(
          _extractText,
          systemPrompt: '你是记账助手。从用户文本中抽取每一笔真实收支，只输出 JSON 数组，'
              '不要解释。元素形如 {"amount":正数,"type":"income或expense","category":"分类","note":"备注"}。',
          temperature: 0.1,
          logTag: 'PresetLive',
        );
        expect(reply, contains('1280'), reason: reply);
        expect(reply, contains('5000'), reason: reply);
      }, timeout: const Timeout(Duration(seconds: 150)));

      test('原生工具调用给出结构化 tool_calls 且相对时间换算正确', () async {
        if (apiKey.isEmpty) return markTestSkipped('未给 key');
        final names = <String>[];
        final args = StringBuffer();
        await for (final chunk in AIProviderFactory.chatWithToolsStream(
          messages: [
            {
              'role': 'system',
              'content': '今天是 2026-10-04。回答前必须先调用工具 get_period_overview，'
                  '把相对时间按今天换算成 start 和 end。'
            },
            {'role': 'user', 'content': '上个月我在餐饮上一共花了多少？'},
          ],
          tools: _tools,
          logTag: 'PresetLive',
        )) {
          for (final choice in (chunk['choices'] as List? ?? const [])) {
            final delta = (choice as Map)['delta'];
            if (delta is! Map) continue;
            for (final call in (delta['tool_calls'] as List? ?? const [])) {
              final fn = (call as Map)['function'];
              if (fn is! Map) continue;
              if (fn['name'] is String) names.add(fn['name'] as String);
              if (fn['arguments'] is String) args.write(fn['arguments']);
            }
          }
        }
        expect(names, contains('get_period_overview'));
        expect(args.toString(), contains('2026-09'), reason: args.toString());
      }, timeout: const Timeout(Duration(seconds: 150)));

      test('支付截图读得出实付金额', () async {
        if (apiKey.isEmpty) return markTestSkipped('未给 key');
        if (preset.visionModel.isEmpty) return markTestSkipped('该预设无视觉模型');
        final reply = await AIProviderFactory.vision(
          File('test/fixtures/payment_screenshot.jpg'),
          '这张支付截图实付多少钱？只输出金额数字。',
          logTag: 'PresetLive',
        );
        expect(reply.replaceAll(',', ''), contains('128.5'), reason: reply);
      }, timeout: const Timeout(Duration(seconds: 200)));
    });
  }
}

/// 只留这一家服务商，能力绑定指到它自己的 id（留 null 会退回智谱默认）。
Future<void> _bind(AIModelPreset preset, String apiKey) async {
  final provider = preset.toProvider().copyWith(apiKey: apiKey);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ai_providers_v2', jsonEncode([provider.toJson()]));
  await prefs.setString(
    'ai_capability_binding_v2',
    jsonEncode(AICapabilityBinding(
      textProviderId: provider.id,
      visionProviderId: provider.visionModel.isEmpty ? null : provider.id,
    ).toJson()),
  );
}
