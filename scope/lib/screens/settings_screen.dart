import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/screens/ai_playground_screen.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Settings for AI, privacy, data retention, and developer tools.
class SettingsScreen extends ConsumerWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  String _getRetentionLabel(int days) {
    switch (days) {
      case 1:
        return '24 Hours (1 Day)';
      case 3:
        return '3 Days';
      case 7:
        return '7 Days (Default)';
      case 14:
        return '14 Days';
      case 30:
        return '30 Days';
      case 90:
        return '90 Days';
      case -1:
      case 0:
        return 'Unlimited';
      default:
        return '$days Days';
    }
  }

  String _getQuotaLabel(int count) {
    switch (count) {
      case 250:
        return '250 Items';
      case 500:
        return '500 Items';
      case 1000:
        return '1,000 Items';
      case 2500:
        return '2,500 Items';
      case 5000:
        return '5,000 Items';
      case -1:
      case 0:
        return 'Unlimited (Default)';
      default:
        return '$count Items';
    }
  }

  void _showGhostAiDialog(
    BuildContext context,
    AppSettingsState settings,
    AppSettingsNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghost AI Engine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On-device hybrid classification pipeline combining heuristic rules and neural models.',
            ),
            const SizedBox(height: AppSpacing.md),
            StatefulBuilder(
              builder: (context, setState) {
                return SwitchListTile(
                  title: const Text('Telemetry & Diagnostic Logs'),
                  subtitle: const Text('Record trace explanations locally'),
                  value: settings.telemetryEnabled,
                  onChanged: (val) async {
                    await notifier.setTelemetryEnabled(val);
                    setState(() {});
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScopeNavigator.push(
                context,
                DiagnosticScreen(engine: controller.engine),
              );
            },
            child: const Text('Open Diagnostics'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTelemetryDialog(
    BuildContext context,
    AppSettingsState settings,
    AppSettingsNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Telemetry & Privacy'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All notification processing and model inferences execute 100% on-device.',
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Diagnostic Event Logging'),
                  subtitle: const Text(
                    'Record pipeline execution trace and latency metrics locally',
                  ),
                  value: settings.telemetryEnabled,
                  onChanged: (val) async {
                    await notifier.setTelemetryEnabled(val);
                    if (context.mounted) {
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showRetentionDialog(
    BuildContext context,
    AppSettingsState settings,
    AppSettingsNotifier notifier,
  ) {
    final options = [1, 3, 7, 14, 30, 90, -1];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data Retention Window'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((days) {
                return RadioListTile<int>(
                  title: Text(_getRetentionLabel(days)),
                  value: days,
                  groupValue: settings.retentionDays,
                  onChanged: (val) async {
                    if (val != null) {
                      await notifier.setRetentionDays(val);
                      await controller.runBackgroundCleanup();
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Retention window set to ${_getRetentionLabel(val)}',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showQuotaDialog(
    BuildContext context,
    AppSettingsState settings,
    AppSettingsNotifier notifier,
  ) {
    final options = [250, 500, 1000, 2500, 5000, -1];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Storage Quota Limit'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((count) {
                return RadioListTile<int>(
                  title: Text(_getQuotaLabel(count)),
                  value: count,
                  groupValue: settings.storageQuota,
                  onChanged: (val) async {
                    if (val != null) {
                      await notifier.setStorageQuota(val);
                      await controller.runBackgroundCleanup();
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Storage quota limit set to ${_getQuotaLabel(val)}',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Settings',
              subtitle: 'AI, privacy, and developer tools.',
            ),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.psychology_outlined,
                    title: 'Ghost AI Engine',
                    subtitle: settings.telemetryEnabled
                        ? 'On-device hybrid analysis pipeline'
                        : 'On-device pipeline (Telemetry disabled)',
                    onTap: () =>
                        _showGhostAiDialog(context, settings, settingsNotifier),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.shield_outlined,
                    title: 'Telemetry & Privacy',
                    subtitle: settings.telemetryEnabled
                        ? 'Diagnostic logging enabled (100% on-device)'
                        : 'Diagnostic logging disabled',
                    onTap: () => _showTelemetryDialog(
                      context,
                      settings,
                      settingsNotifier,
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.auto_delete_outlined,
                    title: 'Data Retention Window',
                    subtitle: _getRetentionLabel(settings.retentionDays),
                    onTap: () => _showRetentionDialog(
                      context,
                      settings,
                      settingsNotifier,
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.storage_outlined,
                    title: 'Storage Quota Limit',
                    subtitle: _getQuotaLabel(settings.storageQuota),
                    onTap: () =>
                        _showQuotaDialog(context, settings, settingsNotifier),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'Notification Access',
                    subtitle: controller.isListenerEnabled
                        ? 'Enabled'
                        : 'Not enabled',
                    onTap: controller.openNotificationSettings,
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
                      DiagnosticScreen(engine: controller.engine),
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
