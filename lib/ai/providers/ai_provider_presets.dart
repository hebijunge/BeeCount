import 'ai_provider_config.dart';

/// 内置服务商预设。
///
/// 随应用分发、在「服务商管理」里自动出现。名称 / Base URL / 三个模型名全部可改，
/// 只有 API Key 要用户自己申请；不可删除（免得误删后再也找不回来）。
///
/// 进这份名单的门槛：2026-10-04 用记账真实负载逐项实测过——中文流水抽取 JSON、
/// 带 system 的原生工具调用（流式，且相对时间要换算对）、base64 支付截图读数，
/// 三项全过才收。端砚 intern-s2 工具调用没问题但抽取 99s 超时、截图读数空回复，
/// 故未收录；AMD/Kilo/OpenRouter 的原因写在提交说明里。
class AIModelPreset {
  const AIModelPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.textModel,
    this.visionModel = '',
    this.audioModel = '',
    this.protocol = AIServiceProviderConfig.protocolOpenAI,
    this.textModelChoices = const <String>[],
    this.visionModelChoices = const <String>[],
    this.audioModelChoices = const <String>[],
    this.keyUrl = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final String textModel;
  final String visionModel;
  final String audioModel;

  /// `zhipu` 走官方 SDK（语音转文字只有它有），其余按 OpenAI 兼容协议裸调。
  final String protocol;

  /// 实测可用的候选模型，点一下就填进输入框。
  final List<String> textModelChoices;
  final List<String> visionModelChoices;
  final List<String> audioModelChoices;

  /// 申请 API Key 的页面，空则不显示「获取 Key」按钮。
  final String keyUrl;

  AIServiceProviderConfig toProvider() => AIServiceProviderConfig(
        id: id,
        name: name,
        isBuiltIn: true,
        baseUrl: baseUrl,
        textModel: textModel,
        visionModel: visionModel,
        audioModel: audioModel,
        protocol: protocol,
        createdAt: DateTime.utc(2024, 1, 1),
      );
}

/// 预设顺序即列表顺序，智谱排第一（语音能力目前只有它可用）。
const List<AIModelPreset> kAiProviderPresets = <AIModelPreset>[
  AIModelPreset(
    id: 'zhipu_glm',
    name: '智谱GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    textModel: 'glm-4-flash',
    visionModel: 'glm-4v-flash',
    audioModel: 'glm-4-voice',
    protocol: AIServiceProviderConfig.protocolZhipu,
    textModelChoices: <String>[
      'glm-4-flash',
      'glm-4-flash-250414',
      'glm-4.7-flash',
      'glm-4.5-flash',
    ],
    visionModelChoices: <String>[
      'glm-4v-flash',
      'glm-4.6v-flash',
    ],
    audioModelChoices: <String>['glm-4-voice'],
    keyUrl: 'https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys',
  ),
  AIModelPreset(
    id: 'requesty_free',
    name: 'Requesty 免费池',
    baseUrl: 'https://router.requesty.ai/v1',
    textModel: 'nvidia/nemotron-3-super-120b-a12b',
    visionModel: 'google/gemma-4-31b-it',
    textModelChoices: <String>[
      'nvidia/nemotron-3-super-120b-a12b',
      'nvidia/nemotron-3.5-lightning-30b-a3b',
      'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
    ],
    visionModelChoices: <String>[
      'google/gemma-4-31b-it',
      'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
    ],
    keyUrl: 'https://app.requesty.ai/api-keys',
  ),
  AIModelPreset(
    id: 'xiaohongshu_dots',
    name: '小红书点点',
    baseUrl: 'https://note3-prev-api.askdiandian.com/v1',
    textModel: 'dots3-note-prev',
    visionModel: 'dots3-note-prev',
    textModelChoices: <String>['dots3-note-prev'],
    visionModelChoices: <String>['dots3-note-prev'],
    keyUrl: 'https://dots.ai/platform/apikeys',
  ),
];

/// 按 id 找预设；用户自建的、或 id 已被改名的服务商返回 null。
AIModelPreset? aiPresetById(String id) {
  for (final preset in kAiProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
