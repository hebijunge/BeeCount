import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../providers/theme_providers.dart';
import '../../providers/ai_config_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ai/providers/ai_provider_config.dart';
import '../../ai/providers/ai_provider_manager.dart';
import '../../ai/privacy/ai_privacy_consent.dart';
import '../../widgets/ai/ai_privacy_consent_dialog.dart';
import 'ai_prompt_edit_page.dart';
import 'ai_provider_manage_page.dart';

/// AI智能识别设置页面
class AISettingsPage extends ConsumerStatefulWidget {
  const AISettingsPage({super.key});

  @override
  ConsumerState<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends ConsumerState<AISettingsPage> {
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    // 存量用户:升级前已开启 AI 但从未同意第三方数据共享 → 进入设置页补弹一次。
    // 其它直接使用 AI 的入口由 AIProviderFactory 的二道关兜底(未同意即中止)。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final enabled = ref.read(aiConfigProvider).enabled;
      if (!enabled) return;
      if (await AiPrivacyConsentStore.isConsented()) return;
      if (!mounted) return;
      final agreed = await ensureAiPrivacyConsent(context, ref);
      if (!agreed && mounted) {
        await ref.read(aiConfigProvider.notifier).setEnabled(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(aiConfigProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.aiSettingsTitle,
            subtitle: l10n.aiSettingsSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                // 1. 总开关
                _buildEnableSection(config),
                SizedBox(height: 8.0.scaled(context, ref)),

                // 2. 服务商管理入口
                _buildProviderManageEntry(),
                SizedBox(height: 8.0.scaled(context, ref)),

                // 3. 能力绑定
                _buildCapabilityBindingSection(),
                SizedBox(height: 8.0.scaled(context, ref)),

                // 4. 高级设置（可折叠）
                _buildAdvancedSettingsSection(config),

                SizedBox(height: 32.0.scaled(context, ref)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 1. 总开关区域
  Widget _buildEnableSection(AIConfigData config) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(aiConfigProvider.notifier);
    final primaryColor = ref.watch(primaryColorProvider);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            value: config.enabled,
            onChanged: (value) async {
              if (value) {
                final agreed = await ensureAiPrivacyConsent(context, ref);
                if (!agreed) return; // 未同意:保持关闭
              }
              await notifier.setEnabled(value);
              if (mounted) {
                showToast(context,
                    value ? l10n.aiEnableToastOn : l10n.aiEnableToastOff);
              }
            },
            title: Text(
              l10n.aiEnableTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(l10n.aiEnableSubtitle),
            activeColor: primaryColor,
          ),
          // v3.2.1 删 OCR 后,图片识别完全走 AI 视觉,无需用户开关。原「上传
          // 图片到 AI」(useVision)开关在此移除;底层 pref key 保留以兼容
          // 老配置导入导出。
        ],
      ),
    );
  }

  /// 2. 服务商管理入口
  Widget _buildProviderManageEntry() {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.cloud_outlined, color: primaryColor),
        title: Text(
          l10n.aiProviderManageTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(l10n.aiProviderManageSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AIProviderManagePage()),
          );
          // 刷新能力绑定和服务商列表
          ref.read(aiCapabilityBindingRefreshProvider.notifier).state++;
          ref.read(aiProviderListForCapabilityRefreshProvider.notifier).state++;
        },
      ),
    );
  }

  /// 3. 能力绑定区域
  Widget _buildCapabilityBindingSection() {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final bindingAsync = ref.watch(aiCapabilityBindingProvider);
    final providersAsync = ref.watch(aiProviderListForCapabilityProvider);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.link, size: 20, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  l10n.aiCapabilitySelectTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.aiCapabilitySelectSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: BeeTokens.textTertiary(context),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 根据加载状态显示
          bindingAsync.when(
            data: (binding) => providersAsync.when(
              data: (providers) => _buildCapabilityList(binding, providers),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e'),
              ),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$e'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityList(
    AICapabilityBinding binding,
    List<AIServiceProviderConfig> providers,
  ) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        BeeTokens.cardDivider(context),
        _buildCapabilityTile(
          icon: Icons.chat_outlined,
          title: l10n.aiCapabilityTextChat,
          subtitle: l10n.aiCapabilityTextChatDesc,
          currentProviderId: binding.textProviderId,
          providers: providers,
          capabilityType: AICapabilityType.text,
        ),
        BeeTokens.cardDivider(context),
        _buildCapabilityTile(
          icon: Icons.image_outlined,
          title: l10n.aiCapabilityImageUnderstand,
          subtitle: l10n.aiCapabilityImageUnderstandDesc,
          currentProviderId: binding.visionProviderId,
          providers: providers,
          capabilityType: AICapabilityType.vision,
        ),
        BeeTokens.cardDivider(context),
        _buildCapabilityTile(
          icon: Icons.mic_outlined,
          title: l10n.aiCapabilitySpeechToText,
          subtitle: l10n.aiCapabilitySpeechToTextDesc,
          currentProviderId: binding.speechProviderId,
          providers: providers,
          capabilityType: AICapabilityType.speech,
        ),
      ],
    );
  }

  Widget _buildCapabilityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String? currentProviderId,
    required List<AIServiceProviderConfig> providers,
    required AICapabilityType capabilityType,
  }) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    // 根据能力类型过滤支持的服务商
    final supportedProviders =
        providers.where((p) => p.supports(capabilityType)).toList();

    // 「自动」不绑死某一家：按和调用侧同一套规则现场解析出用谁
    final isAuto = AICapabilityBinding.isAuto(currentProviderId);
    final autoPick =
        isAuto ? AIProviderManager.pickAuto(providers, capabilityType) : null;
    final currentProvider = isAuto
        ? (autoPick ?? AIServiceProviderConfig.zhipuDefault)
        : providers.firstWhere(
            (p) => p.id == currentProviderId,
            orElse: () => AIServiceProviderConfig.zhipuDefault,
          );
    final trailingLabel = !isAuto
        ? currentProvider.name
        : (autoPick == null
            ? l10n.aiCapabilityAutoNone
            : l10n.aiCapabilityAutoUsing(autoPick.name));

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 22, color: primaryColor),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              trailingLabel,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: BeeTokens.textSecondary(context),
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: () => _showProviderSelectionDialog(
        title: title,
        providers: supportedProviders,
        currentProviderId: currentProviderId,
        capabilityType: capabilityType,
      ),
    );
  }

  void _showProviderSelectionDialog({
    required String title,
    required List<AIServiceProviderConfig> providers,
    required String? currentProviderId,
    required AICapabilityType capabilityType,
  }) {
    final l10n = AppLocalizations.of(context);

    final isAuto = AICapabilityBinding.isAuto(currentProviderId);

    showDialog(
      context: context,
      builder: (dialogContext) {
        Future<void> bind(String providerId, String label) async {
          Navigator.pop(dialogContext);
          await AIProviderManager.setCapabilityProvider(
            capabilityType,
            providerId,
          );
          ref.read(aiCapabilityBindingRefreshProvider.notifier).state++;
          if (mounted) {
            showToast(context, '${l10n.commonSaved}: $label');
          }
        }

        return AlertDialog(
          title: Text(title),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBindingOption(
                  selected: isAuto,
                  name: l10n.aiCapabilityAuto,
                  desc: l10n.aiCapabilityAutoDesc,
                  onPick: () => bind(
                    AICapabilityBinding.autoProviderId,
                    l10n.aiCapabilityAuto,
                  ),
                ),
                for (final provider in providers)
                  _buildBindingOption(
                    selected: provider.id == currentProviderId,
                    name: provider.name,
                    desc: provider.isValid ? null : l10n.aiProviderNoApiKey,
                    warn: !provider.isValid,
                    onPick: () => bind(provider.id, provider.name),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
    );
  }

  /// 绑定选择弹窗里的一行（「自动」和各服务商共用）
  Widget _buildBindingOption({
    required bool selected,
    required String name,
    String? desc,
    bool warn = false,
    required VoidCallback onPick,
  }) {
    final primaryColor = ref.read(primaryColorProvider);

    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? primaryColor : BeeTokens.textTertiary(context),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? primaryColor : BeeTokens.textPrimary(context),
        ),
      ),
      subtitle: desc == null
          ? null
          : Text(
              desc,
              style: TextStyle(
                fontSize: 12,
                color:
                    warn ? Colors.orange[700] : BeeTokens.textTertiary(context),
              ),
            ),
      onTap: onPick,
    );
  }

  /// 高级设置（可折叠）
  Widget _buildAdvancedSettingsSection(AIConfigData config) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final notifier = ref.read(aiConfigProvider.notifier);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _advancedExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _advancedExpanded = expanded);
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(Icons.tune, size: 20, color: primaryColor),
          title: Text(
            l10n.aiPromptAdvancedSettings,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l10n.aiAdvancedSettingsDesc,
            style: TextStyle(
              fontSize: 12,
              color: BeeTokens.textTertiary(context),
            ),
          ),
          children: [
            BeeTokens.cardDivider(context),

            // === 执行策略 ===
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.route_outlined,
                      size: 18, color: BeeTokens.textSecondary(context)),
                  const SizedBox(width: 8),
                  Text(
                    l10n.aiStrategyTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),

            RadioListTile<AIStrategy>(
              value: AIStrategy.cloudFirst,
              groupValue: config.strategy,
              onChanged: (value) async {
                if (value != null) {
                  await notifier.setStrategy(value);
                  if (mounted) {
                    showToast(context,
                        l10n.aiStrategySwitched(l10n.aiStrategyCloudFirst));
                  }
                }
              },
              title: Text(l10n.aiStrategyCloudFirst,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.aiStrategyCloudFirstDesc,
                  style: const TextStyle(fontSize: 12)),
              activeColor: primaryColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
            ),
            RadioListTile<AIStrategy>(
              value: AIStrategy.cloudOnly,
              groupValue: config.strategy,
              onChanged: (value) async {
                if (value != null) {
                  await notifier.setStrategy(value);
                  if (mounted) {
                    showToast(context,
                        l10n.aiStrategySwitched(l10n.aiStrategyCloudOnly));
                  }
                }
              },
              title: Text(l10n.aiStrategyCloudOnly,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.aiStrategyCloudOnlyDesc,
                  style: const TextStyle(fontSize: 12)),
              activeColor: primaryColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
            ),
            RadioListTile<AIStrategy>(
              value: AIStrategy.localFirst,
              groupValue: config.strategy,
              onChanged: null,
              title: Text(l10n.aiStrategyLocalFirst,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.aiStrategyUnavailable,
                  style: const TextStyle(fontSize: 12)),
              activeColor: primaryColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
            ),
            RadioListTile<AIStrategy>(
              value: AIStrategy.localOnly,
              groupValue: config.strategy,
              onChanged: null,
              title: Text(l10n.aiStrategyLocalOnly,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.aiStrategyUnavailable,
                  style: const TextStyle(fontSize: 12)),
              activeColor: primaryColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
            ),

            BeeTokens.cardDivider(context),

            // 历史「本地模型(训练中)」占位 entry 已删除(2026-05-24)。本地 AI 视觉
            // 未来走 Apple Foundation Models / Gemini Nano(平台原生 SDK,非 tflite),
            // 详见 .docs/on-device-vlm/README.md。

            // === 自定义提示词 ===
            ListTile(
              dense: true,
              leading: Icon(Icons.edit_note, size: 20, color: primaryColor),
              title: Text(l10n.aiPromptEditEntry,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.aiPromptEditEntryDesc,
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AIPromptEditPage()),
                );
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
