import 'ai_provider_config.dart';

/// 内置服务商预设。
///
/// 随应用分发、在「服务商管理」里自动出现。名称 / Base URL / 三个模型名全部可改，
/// 只有 API Key 要用户自己申请；不可删除（免得误删后再也找不回来）。
///
/// 进这份名单的门槛：用记账真实负载逐项实测过——中文流水抽取 JSON、带 system 的
/// 原生工具调用（相对时间要换算对）、base64 支付截图读金额。2026-10-04 实测通过的
/// 就是下面这几家（单项耗时写进各家说明）。
/// 没进来的只有 OpenRouter 与 agnes：本机到这两个域名的请求被中间设备改写成
/// m.baidu.com，拿不到能用的证据。
///
/// AMD 走 [AIModelPreset.localOnly]：条款禁 resell/proxy、明说不可用于生产，
/// 所以它只出现在构建期注入过它 key 的本机包里，公开包行为不变。
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
    this.localOnly = false,
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

  /// 只进本机自建的包：需要构建期注入该家 key 才会出现在列表里。
  ///
  /// 给的是条款不允许分发场景的服务商（AMD 明说不可用于生产、禁 resell/proxy）。
  /// 公开仓库和 GitHub 上的包没有它的 key，也就永远看不到这一条。
  final bool localOnly;

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
  AIModelPreset(
    id: 'agnes',
    name: 'Agnes',
    baseUrl: 'https://api.agnes-ai.cn/v1',
    textModel: 'agnes-3.0-flash',
    visionModel: 'agnes-3.0-flash',
    textModelChoices: <String>['agnes-3.0-flash'],
    visionModelChoices: <String>['agnes-3.0-flash'],
    keyUrl: 'https://agnes-ai.cn',
  ),
  AIModelPreset(
    id: 'sensenova',
    name: '商汤 SenseNova',
    baseUrl: 'https://token.sensenova.cn/v1',
    textModel: 'sensenova-6.8-flash-lite',
    visionModel: 'sensenova-6.8-flash-lite',
    textModelChoices: <String>[
      'sensenova-6.8-flash-lite',
      'glm-5.2',
      'deepseek-v4-flash',
      'deepseek-flash',
      'kimi-k3',
    ],
    visionModelChoices: <String>['sensenova-6.8-flash-lite'],
    keyUrl: 'https://platform.sensenova.cn',
  ),
  AIModelPreset(
    id: 'pollinations',
    name: 'Pollinations',
    baseUrl: 'https://gen.pollinations.ai/v1',
    textModel: 'openai/gpt-6-luna',
    visionModel: 'openai/gpt-6-luna',
    textModelChoices: <String>[
      'openai/gpt-6-luna',
      'openai/gpt-5.4-nano',
      'deepseek/deepseek-v4.1-flash',
      'z-ai/glm-5.3-flash',
      'qwen/qwen3-coder-30b-a3b-instruct',
    ],
    visionModelChoices: <String>[
      'openai/gpt-6-luna',
      'deepseek/deepseek-v4.1-flash',
      'openai/gpt-5.4-nano',
    ],
    keyUrl: 'https://pollinations.ai',
  ),
  AIModelPreset(
    id: 'z_ai',
    name: '智谱 Z.ai 国际站',
    baseUrl: 'https://api.z.ai/api/paas/v4',
    textModel: 'glm-4.7-flash',
    // 免费可调的只有 flash 系文本模型；4.6v-flash 要余额，所以不给视觉模型。
    textModelChoices: <String>['glm-4.7-flash', 'glm-4.5-flash'],
    keyUrl: 'https://z.ai',
  ),
  AIModelPreset(
    id: 'amd_radeon',
    name: 'AMD Radeon 免费池',
    baseUrl: 'https://developer.amd.com.cn/radeon/api/v1',
    textModel: 'DeepSeek-V4-Flash',
    visionModel: 'DeepSeek-V4-Flash-Vision-Exp',
    textModelChoices: <String>[
      'DeepSeek-V4-Flash',
      'Qwen3.8-Flash-Next',
    ],
    visionModelChoices: <String>[
      'DeepSeek-V4-Flash-Vision-Exp',
      'Qwen3.8-Flash-Next',
    ],
    keyUrl: 'https://developer.amd.com.cn/radeon',
    // 条款禁 resell/proxy、明说不可用于生产：只进构建期注入过它 key 的本机包。
    localOnly: true,
  ),
];

/// 这次构建该补哪些预设：`localOnly` 的那几家，只有注入过它的 key 才出现。
List<AIModelPreset> seedablePresets(Map<String, String> localApiKeys) {
  return kAiProviderPresets.where((preset) {
    if (!preset.localOnly) return true;
    return (localApiKeys[preset.id] ?? '').isNotEmpty;
  }).toList();
}

/// 按 id 找预设；用户自建的、或 id 已被改名的服务商返回 null。
AIModelPreset? aiPresetById(String id) {
  for (final preset in kAiProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
