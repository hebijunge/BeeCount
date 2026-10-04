/// 本机私有 AI API Key 的注入点。
///
/// 仓库里这三条永远是空串：key 只在构建时由 `tool/build_local_ai_keys.sh`
/// 从 `ai_keys.local.env`（已 gitignore）经 `--dart-define` 传进来。
/// 所以开源仓库和 GitHub 上的包永远不含凭据。
///
/// 反过来说，**用这个脚本构建出来的 APK 里 key 是明文可提取的**，
/// 那种包只适合自己那几台设备装，不要转给别人。
const Map<String, String> kLocalAiApiKeys = <String, String>{
  'zhipu_glm': String.fromEnvironment('BEE_AI_KEY_ZHIPU'),
  'requesty_free': String.fromEnvironment('BEE_AI_KEY_REQUESTY'),
  'xiaohongshu_dots': String.fromEnvironment('BEE_AI_KEY_DOTS'),
  'intern_discovery': String.fromEnvironment('BEE_AI_KEY_INTERN'),
  'kilo_free': String.fromEnvironment('BEE_AI_KEY_KILO'),
  'amd_radeon': String.fromEnvironment('BEE_AI_KEY_AMD'),
};
