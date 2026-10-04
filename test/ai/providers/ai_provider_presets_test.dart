import 'dart:convert';
import 'dart:io';

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

    test('localOnly 的那几家只在注入过 key 时才参与补齐', () {
      final localOnly = kAiProviderPresets
          .where((p) => p.localOnly)
          .map((p) => p.id)
          .toList();
      expect(localOnly, contains('amd_radeon'));

      expect(seedablePresets(const {}).map((p) => p.id),
          isNot(containsAll(localOnly)));
      final keys = {for (final id in localOnly) id: 'k'};
      expect(seedablePresets(keys).map((p) => p.id), containsAll(localOnly));
      expect(seedablePresets(keys).length, kAiProviderPresets.length);
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
      expect(AIServiceProviderConfig.fromJson(zhipu.toJson()).usesZhipuSdk,
          isTrue);
      expect(zhipu.copyWith(apiKey: 'k').usesZhipuSdk, isTrue);
    });
  });

  group('getProviders 补齐预设', () {
    test('老数据只有智谱时，补出其余预设并落库', () async {
      SharedPreferences.setMockInitialValues({
        'ai_providers_v2': jsonEncode([
          AIServiceProviderConfig.zhipuDefault
              .copyWith(apiKey: 'old-key')
              .toJson(),
        ]),
      });

      final providers = await AIProviderManager.getProviders();
      expect(
          providers.map((p) => p.id),
          containsAll(<String>[
            'zhipu_glm',
            'requesty_free',
            'xiaohongshu_dots',
            'intern_discovery',
            'kilo_free',
          ]));
      expect(
          providers.firstWhere((p) => p.id == 'zhipu_glm').apiKey, 'old-key');

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

      expect(await AIProviderManager.deleteProvider('requesty_free'), isFalse);
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
      // AMD 是 localOnly：没注入它的 key 就不该出现在这里
      expect(providers.length, seedablePresets(const {}).length);
      expect(providers.map((p) => p.id), isNot(contains('amd_radeon')));
    });
  });

  group('内置预设置顶', () {
    AIServiceProviderConfig custom(String id) => AIServiceProviderConfig(
          id: id,
          name: id,
          baseUrl: 'https://internal.example.com/v1',
          textModel: 'm',
          createdAt: DateTime(2026, 1, 1),
        );

    test('纯函数：预设按目录顺序在前，自建保持原有先后', () {
      final ordered = AIProviderManager.sortBuiltInFirst([
        custom('mine_a'),
        aiPresetById('xiaohongshu_dots')!.toProvider(),
        custom('mine_b'),
        aiPresetById('requesty_free')!.toProvider(),
        aiPresetById('zhipu_glm')!.toProvider(),
      ]);

      expect(ordered.map((p) => p.id), <String>[
        'zhipu_glm',
        'requesty_free',
        'xiaohongshu_dots',
        'mine_a',
        'mine_b',
      ]);
    });

    test('目录外的内置项排在预设之后、自建之前', () {
      final legacy = AIServiceProviderConfig(
        id: 'legacy_built_in',
        name: '老内置',
        isBuiltIn: true,
        createdAt: DateTime(2024, 1, 1),
      );
      final ordered = AIProviderManager.sortBuiltInFirst(
          [custom('mine_a'), legacy, aiPresetById('zhipu_glm')!.toProvider()]);
      expect(ordered.map((p) => p.id),
          <String>['zhipu_glm', 'legacy_built_in', 'mine_a']);
    });

    test('自建服务商存在时，读出来内置在最前并且顺序落库', () async {
      SharedPreferences.setMockInitialValues({
        'ai_providers_v2': jsonEncode([
          custom('mine_a').toJson(),
          AIServiceProviderConfig.zhipuDefault.toJson(),
          aiPresetById('requesty_free')!.toProvider().toJson(),
          aiPresetById('xiaohongshu_dots')!.toProvider().toJson(),
        ]),
      });

      final providers = await AIProviderManager.getProviders();
      expect(providers.first.id, 'zhipu_glm');
      expect(providers.last.id, 'mine_a');

      // 再读一次不该来回抖动，也不该再写库
      final again = await AIProviderManager.getProviders();
      expect(again.map((p) => p.id), providers.map((p) => p.id));
      final prefs = await SharedPreferences.getInstance();
      expect(
          (jsonDecode(prefs.getString('ai_providers_v2')!) as List)
              .map((p) => (p as Map)['id']),
          providers.map((p) => p.id));
    });
  });

  group('构建期注入的本机 key', () {
    test('只给还没配 key 的服务商填，填过的不动', () {
      final providers = [
        AIServiceProviderConfig.zhipuDefault.copyWith(apiKey: 'user-own'),
        aiPresetById('requesty_free')!.toProvider(),
        aiPresetById('xiaohongshu_dots')!.toProvider().copyWith(apiKey: ''),
      ];
      final (filled, changed) = AIProviderManager.applyLocalApiKeys(providers, {
        'zhipu_glm': 'injected',
        'requesty_free': 'injected',
        'xiaohongshu_dots': 'injected',
        'not_a_preset': 'injected',
      });

      expect(changed, isTrue);
      expect(filled[0].apiKey, 'user-own');
      expect(filled[1].apiKey, 'injected');
      expect(filled[2].apiKey, 'injected');
    });

    test('没注入（空 map / 空串）时不改内容，也不触发落库', () {
      final providers = [aiPresetById('requesty_free')!.toProvider()];
      final (same, changed) =
          AIProviderManager.applyLocalApiKeys(providers, const {});
      expect(changed, isFalse);
      expect(same.single.apiKey, isEmpty);

      expect(
          AIProviderManager.applyLocalApiKeys(providers, {'requesty_free': ''})
              .$2,
          isFalse);
    });

    test('补齐预设时一并带上注入的 key', () async {
      SharedPreferences.setMockInitialValues({});
      final providers = await AIProviderManager.getProviders();
      // 普通 flutter test 不带 --dart-define，所以这里应当全是空 key；
      // 真注入由上一条用例和构建脚本负责。
      expect(providers.every((p) => p.apiKey.isEmpty), isTrue);
    });

    test('注入点文件里不许出现明文 key', () {
      final src = File('lib/ai/providers/ai_provider_local_keys.dart')
          .readAsStringSync();
      expect(src, contains('String.fromEnvironment'));
      // 形如 'hex.随机段' 的智谱 key、或直接把值写死成字符串字面量
      expect(
          RegExp(r"'[0-9a-f]{24,}\.[A-Za-z0-9]{12,}'").hasMatch(src), isFalse);
      expect(RegExp(r"BEE_AI_KEY_\w+'\s*,\s*'").hasMatch(src), isFalse);
    });
  });
}
