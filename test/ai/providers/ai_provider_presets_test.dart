import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:beecount/ai/providers/ai_provider_presets.dart';

/// 内置服务商预设：随包分发、自动补齐、字段可编辑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('预设目录', () {
    test('id 唯一，且和智谱内置 id 不冲突', () {
      final ids = kAiProviderPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, contains('zhipu_glm'));
    });

    test('每项都有可用文本模型，地址是 https，可选模型都在目录里', () {
      for (final preset in kAiProviderPresets) {
        expect(preset.baseUrl, startsWith('https://'));
        expect(preset.textModel, isNotEmpty, reason: preset.id);
        expect(preset.keyUrl, anyOf(isEmpty, startsWith('https://')));
        expect(preset.textModelChoices, contains(preset.textModel),
            reason: '${preset.id} 默认文本模型应当出现在候选里');
        if (preset.visionModel.isNotEmpty) {
          expect(preset.visionModelChoices, contains(preset.visionModel),
              reason: '${preset.id} 默认视觉模型应当出现在候选里');
        }
      }
    });

    test('只有智谱走官方 SDK，其余按 OpenAI 兼容协议', () {
      for (final preset in kAiProviderPresets) {
        expect(preset.toProvider().usesZhipuSdk, preset.id == 'zhipu_glm',
            reason: preset.id);
      }
    });

    test('预设转成的服务商是内置的、没有 API Key', () {
      final provider = kAiProviderPresets.first.toProvider();
      expect(provider.isBuiltIn, isTrue);
      expect(provider.isValid, isFalse);
      expect(aiPresetById('no_such_provider'), isNull);
    });
  });

  group('服务商 JSON 协议字段', () {
    test('缺 protocol 时按 id 兜底：智谱回 zhipu，其余回 openai', () {
      final legacy = jsonDecode(jsonEncode({
        'id': 'zhipu_glm',
        'name': '智谱GLM',
        'createdAt': '2024-01-01T00:00:00.000',
      })) as Map<String, dynamic>;
      expect(AIServiceProviderConfig.fromJson(legacy).usesZhipuSdk, isTrue);

      final other = jsonDecode(jsonEncode({
        'id': 'requesty_free',
        'name': 'Requesty 免费池',
        'createdAt': '2024-01-01T00:00:00.000',
      })) as Map<String, dynamic>;
      expect(AIServiceProviderConfig.fromJson(other).usesZhipuSdk, isFalse);
    });

    test('toJson / copyWith 不丢 protocol', () {
      final zhipu = AIServiceProviderConfig.zhipuDefault;
      expect(zhipu.toJson()['protocol'], 'zhipu');
      expect(AIServiceProviderConfig.fromJson(zhipu.toJson()).usesZhipuSdk, isTrue);
      expect(zhipu.copyWith(apiKey: 'k').usesZhipuSdk, isTrue);
    });
  });

  group('getProviders 补齐预设', () {
    test('老数据只有智谱时，补出其余预设并落库', () async {
      SharedPreferences.setMockInitialValues({
        'ai_providers_v2': jsonEncode([
          AIServiceProviderConfig.zhipuDefault.copyWith(apiKey: 'old-key').toJson(),
        ]),
      });

      final providers = await AIProviderManager.getProviders();
      expect(providers.map((p) => p.id),
          containsAll(<String>['zhipu_glm', 'requesty_free', 'xiaohongshu_dots']));
      expect(providers.firstWhere((p) => p.id == 'zhipu_glm').apiKey, 'old-key');

      // 补齐结果已写回 prefs（第二次读不应再增长）
      final again = await AIProviderManager.getProviders();
      expect(again.length, providers.length);
    });

    test('用户改过的预设不被覆盖回默认值', () async {
      final edited = AIServiceProviderConfig.zhipuDefault.copyWith(
        apiKey: 'k',
        textModel: 'glm-4.7-flash',
        baseUrl: 'https://proxy.example.com/api/paas/v4',
      );
      SharedPreferences.setMockInitialValues({
        'ai_providers_v2': jsonEncode([edited.toJson()]),
      });

      final providers = await AIProviderManager.getProviders();
      final zhipu = providers.firstWhere((p) => p.id == 'zhipu_glm');
      expect(zhipu.textModel, 'glm-4.7-flash');
      expect(zhipu.baseUrl, 'https://proxy.example.com/api/paas/v4');
      expect(zhipu.usesZhipuSdk, isTrue);
    });

    test('预设不能删除，改回的默认值保留 API Key', () async {
      SharedPreferences.setMockInitialValues({});
      await AIProviderManager.getProviders();

      expect(
          await AIProviderManager.deleteProvider('requesty_free'), isFalse);
      final providers = await AIProviderManager.getProviders();
      expect(providers.map((p) => p.id), contains('requesty_free'));

      await AIProviderManager.updateProvider(
          AIServiceProviderConfig.zhipuDefault.copyWith(apiKey: 'keep-me'));
      await AIProviderManager.updateProvider(
          kAiProviderPresets.first.toProvider().copyWith(apiKey: 'keep-me'));
      final restored = await AIProviderManager.getProvider('zhipu_glm');
      expect(restored?.apiKey, 'keep-me');
    });

    test('首次使用时预设直接进入列表', () async {
      SharedPreferences.setMockInitialValues({});

      final providers = await AIProviderManager.getProviders();
      expect(providers.first.id, 'zhipu_glm');
      expect(providers.length, kAiProviderPresets.length);
    });
  });
}
