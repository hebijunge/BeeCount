import 'ai_provider_config.dart';

/// 内置服务商预设。
///
/// 随应用分发、在「服务商管理」里自动出现。名称 / Base URL / 三个模型名全部可改，
/// 只有 API Key 要用户自己申请；不可删除（免得误删后再也找不回来）。
///
/// 进这份名单的门槛：用记账真实负载逐项实测过——中文流水抽取 JSON、带 system 的
/// 原生工具调用（相对时间要换算对）、base64 支付截图读金额。2026-10-04 实测通过的
/// 就是下面这五家（含单项耗时写进各家说明）。
/// 没进来的：AMD（条款禁 resell/proxy、不可用于生产）、OpenRouter 与 agnes
/// （本机到这两个域名的请求被中间设备改写成 m.baidu.com，无法验证）。
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
  AIModelPreset(
    id: 'intern_discovery',
    name: '书生·端砚',
    baseUrl: 'https://discovery-api.intern-ai.org.cn/v1',
    // 同一家里 Atria 抽取 16s、intern-s2 要 77s，所以默认文本模型给 Atria；
    // 读图反过来只有 intern-s2 支持，就让它承担视觉。
    textModel: 'Atria-Dawn-Preview',
    visionModel: 'intern-s2',
    textModelChoices: <String>['Atria-Dawn-Preview', 'intern-s2'],
    visionModelChoices: <String>['intern-s2'],
    keyUrl: 'https://intern-ai.org.cn',
  ),
  AIModelPreset(
    id: 'kilo_free',
    name: 'Kilo 免费池',
    baseUrl: 'https://api.kilo.ai/api/openrouter',
    textModel: 'nvidia/nemotron-3-ultra-550b-a55b:free',
    visionModel: 'stepfun/step-3.7-flash:free',
    textModelChoices: <String>[
      'nvidia/nemotron-3-ultra-550b-a55b:free',
      'stealth/space-bunny-alpha',
      'stepfun/step-3.7-flash:free',
    ],
    visionModelChoices: <String>[
      'stepfun/step-3.7-flash:free',
      'stealth/space-bunny-alpha',
    ],
    keyUrl: 'https://kilo.ai',
  ),
];

/// 按 id 找预设；用户自建的、或 id 已被改名的服务商返回 null。
AIModelPreset? aiPresetById(String id) {
  for (final preset in kAiProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
