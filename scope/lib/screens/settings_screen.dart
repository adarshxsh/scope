import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/ai_playground_screen.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Settings for AI, privacy, ingestion guardrails, and developer tools.
class SettingsScreen extends StatelessWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  void _showPackageListDialog({
    required BuildContext context,
    required String title,
    required List<String> packages,
    required ValueChanged<String> onAdd,
    required ValueChanged<String> onRemove,
  }) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: textController,
                      decoration: const InputDecoration(
                        labelText: 'Package or Wildcard Pattern',
                        hintText: 'e.g. com.whatsapp, *.bank.*',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Pattern'),
                        onPressed: () {
                          final input = textController.text.trim();
                          if (input.isNotEmpty) {
                            onAdd(input);
                            textController.clear();
                            setStateDialog(() {});
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Active Rules:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (packages.isEmpty)
                      const Text(
                        'No package patterns configured.',
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      )
                    else
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: packages.map((pkg) {
                          return Chip(
                            label: Text(pkg),
                            onDeleted: () {
                              onRemove(pkg);
                              setStateDialog(() {});
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final guardrails = controller.guardrails;

        return SafeArea(
          child: ScopeScreenBody(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                const SectionHeader(
                  title: 'Settings',
                  subtitle: 'AI, privacy, guardrails, and developer tools.',
                ),
                ScopeSurface(
                  padding: EdgeInsets.zero,
                  elevated: false,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.psychology_outlined,
                        title: 'Ghost AI Engine',
                        subtitle: 'On-device hybrid analysis pipeline',
                        onTap: null,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.shield_outlined,
                        title: 'Privacy',
                        subtitle: 'All analysis runs on your device',
                        onTap: null,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Notification Access',
                        subtitle: controller.isListenerEnabled ? 'Enabled' : 'Not enabled',
                        onTap: controller.openNotificationSettings,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                const SectionLabel(label: 'Ingestion Guardrails & Sensitive Categories'),
                const SizedBox(height: AppSpacing.md),
                ScopeSurface(
                  padding: EdgeInsets.zero,
                  elevated: false,
                  child: Column(
                    children: [
                      _SettingsSwitchTile(
                        icon: Icons.lock_outline,
                        title: 'Exclude OTP & Authentication',
                        subtitle: 'Block 2FA codes & one-time passwords at OS boundary',
                        value: guardrails.excludeOtp,
                        onChanged: controller.setExcludeOtp,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsSwitchTile(
                        icon: Icons.account_balance_outlined,
                        title: 'Exclude Finance & Banking',
                        subtitle: 'Block banking & transaction alerts at OS boundary',
                        value: guardrails.excludeFinance,
                        onChanged: controller.setExcludeFinance,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsSwitchTile(
                        icon: Icons.local_hospital_outlined,
                        title: 'Exclude Health Notifications',
                        subtitle: 'Block medical & appointment alerts at OS boundary',
                        value: guardrails.excludeHealth,
                        onChanged: controller.setExcludeHealth,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsSwitchTile(
                        icon: Icons.miscellaneous_services_outlined,
                        title: 'Exclude System Services',
                        subtitle: 'Block background services & persistent system updates',
                        value: guardrails.excludeSystemServices,
                        onChanged: controller.setExcludeSystemServices,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsSwitchTile(
                        icon: Icons.filter_alt_outlined,
                        title: 'Whitelist Mode Only',
                        subtitle: guardrails.isWhitelistMode
                            ? 'Active: Only allowed packages are captured'
                            : 'Inactive: All packages except blocked ones are captured',
                        value: guardrails.isWhitelistMode,
                        onChanged: controller.setWhitelistMode,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.block_outlined,
                        title: 'Manage Blocked Packages',
                        subtitle: '${guardrails.blockedPackages.length} package pattern(s) blocked',
                        onTap: () => _showPackageListDialog(
                          context: context,
                          title: 'Manage Blocked Package Patterns',
                          packages: guardrails.blockedPackages,
                          onAdd: controller.addBlockedPackage,
                          onRemove: controller.removeBlockedPackage,
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.playlist_add_check_outlined,
                        title: 'Manage Allowed Packages',
                        subtitle: '${guardrails.allowedPackages.length} package pattern(s) allowed',
                        onTap: () => _showPackageListDialog(
                          context: context,
                          title: 'Manage Allowed Package Patterns',
                          packages: guardrails.allowedPackages,
                          onAdd: controller.addAllowedPackage,
                          onRemove: controller.removeAllowedPackage,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                const SectionLabel(label: 'Developer'),
                const SizedBox(height: AppSpacing.md),
                ScopeSurface(
                  padding: EdgeInsets.zero,
                  elevated: false,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.science_outlined,
                        title: 'Load Test Data',
                        subtitle: 'Generate 10 analyzed notifications',
                        onTap: () async {
                          await controller.generateTestData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Test notifications loaded'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.model_training_rounded,
                        title: 'AI Playground (RLHF)',
                        subtitle: 'Post-mortem inspect & reward model',
                        onTap: () => ScopeNavigator.push(
                          context,
                          AiPlaygroundScreen(controller: controller),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.analytics_outlined,
                        title: 'Diagnostics',
                        subtitle: 'Pipeline trace and templates',
                        onTap: () => ScopeNavigator.push(
                          context,
                          DiagnosticScreen(
                            engine: controller.engine,
                            controller: controller,
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.refresh_rounded,
                        title: 'Refresh Notifications',
                        subtitle: 'Pull latest from device',
                        onTap: controller.refresh,
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Clear All Data',
                        subtitle: 'Remove stored notifications',
                        onTap: controller.clearAll,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Scope · AttentionOS',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ScopeIconBox(icon: icon, size: ScopeIconBoxSize.sm),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SwitchListTile(
      secondary: ScopeIconBox(icon: icon, size: ScopeIconBoxSize.sm),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

