// 能力绑定的「自动」：不绑死某一家，调用时按列表顺序现场解析。
//
// 钉住两条容易做错的语义：① 只认「已配好 key 且支持该能力」的服务商，
// 光有模型名没 key 的要跳过（否则用户会在弹窗里等到一个鉴权失败）；
// ② 一家都不满足时返回 null，让上层提示「未配置」，不能静默退回智谱——
// 那样用户以为自己选了自动，实际一直在用另一家。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:beecount/ai/providers/ai_provider_presets.dart';

AIServiceProviderConfig provider(
  String id, {
  bool builtIn = false,
  String apiKey = '',
  String textModel = '',
  String visionModel = '',
  String audioModel = '',
}) =>
    AIServiceProviderConfig(
      id: id,
      name: id,
      isBuiltIn: builtIn,
      apiKey: apiKey,
      baseUrl: 'https://example.com/v1',
      textModel: textModel,
      visionModel: visionModel,
      audioModel: audioModel,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pickAuto 解析规则', () {
    test('按列表顺序取第一个有 key 且支持该能力的', () {
      final providers = [
        provider('a', textModel: 't'), // 没 key，跳过
        provider('b', apiKey: 'k'), // 有 key 但没文本模型，跳过
        provider('c', apiKey: 'k', textModel: 't', visionModel: 'v'),
        provider('d', apiKey: 'k', textModel: 't2'),
      ];

      expect(AIProviderManager.pickAuto(providers, AICapabilityType.text)!.id,
          'c');
      expect(AIProviderManager.pickAuto(providers, AICapabilityType.vision)!.id,
          'c');
    });

    test('能力不同会解析到不同家', () {
      final providers = [
        provider('只有文本', apiKey: 'k', textModel: 't'),
        provider('只有语音', apiKey: 'k', audioModel: 'a'),
      ];
      expect(AIProviderManager.pickAuto(providers, AICapabilityType.text)!.id,
          '只有文本');
      expect(AIProviderManager.pickAuto(providers, AICapabilityType.speech)!.id,
          '只有语音');
    });

    test('一家都不满足时返回 null，不静默退回某家', () {
      expect(
          AIProviderManager.pickAuto(
              [provider('没 key', textModel: 't')], AICapabilityType.text),
          isNull);
      expect(AIProviderManager.pickAuto([], AICapabilityType.vision), isNull);
    });
  });

  group('自动绑定的存取', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('setCapabilityProvider 存 auto 后能读回，三项互不影响', () async {
      await AIProviderManager.setCapabilityProvider(
          AICapabilityType.text, AICapabilityBinding.autoProviderId);
      final binding = await AIProviderManager.getCapabilityBinding();

      expect(binding.textProviderId, AICapabilityBinding.autoProviderId);
      expect(AICapabilityBinding.isAuto(binding.textProviderId), isTrue);
      expect(AICapabilityBinding.isAuto(binding.visionProviderId), isFalse);
    });

    test('自动下 getProviderForCapability 返回解析出来的那一家', () async {
      final zhipu = aiPresetById('zhipu_glm')!.toProvider();
      final dots = aiPresetById('xiaohongshu_dots')!.toProvider();
      SharedPreferences.setMockInitialValues({
        'ai_providers_v2': jsonEncode([
          zhipu.copyWith(apiKey: 'zk').toJson(),
          dots.copyWith(apiKey: 'dk').toJson(),
        ]),
        'ai_capability_binding_v2': jsonEncode(const AICapabilityBinding(
          textProviderId: AICapabilityBinding.autoProviderId,
          visionProviderId: AICapabilityBinding.autoProviderId,
          speechProviderId: AICapabilityBinding.autoProviderId,
        ).toJson()),
      });

      // 智谱排第一且三项都有，所以自动应当落在它身上
      expect(
          (await AIProviderManager.getProviderForCapability(
                  AICapabilityType.text))!
              .id,
          'zhipu_glm');
      expect(
          (await AIProviderManager.getProviderForCapability(
                  AICapabilityType.speech))!
              .id,
          'zhipu_glm');
      expect(
          await AIProviderManager.isCapabilityConfigured(AICapabilityType.text),
          isTrue);
    });

    test('自动但一家都没 key 时返回 null，且 isCapabilityConfigured 为 false', () async {
      SharedPreferences.setMockInitialValues({
        'ai_capability_binding_v2': jsonEncode(const AICapabilityBinding(
          textProviderId: AICapabilityBinding.autoProviderId,
        ).toJson()),
      });

      // 预设会被补齐出来，但都没有 key，所以自动解析不到任何一家
      expect(
          await AIProviderManager.getProviderForCapability(
              AICapabilityType.text),
          isNull);
      expect(
          await AIProviderManager.isCapabilityConfigured(AICapabilityType.text),
          isFalse);
    });
  });
}
