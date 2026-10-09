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

/// Settings for AI, privacy, telemetry retention, storage quotas, and developer tools.
class SettingsScreen extends ConsumerWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  String _formatRetention(int days) {
    if (days == -1) return 'Unlimited (Keep all)';
    if (days == 1) return '1 Day';
    return '$days Days';
  }

  String _formatStorageMb(int mb) {
    if (mb == -1) return 'Unlimited';
    return '$mb MB Ceiling';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(userSettingsProvider);
    final storageStatsAsync = ref.watch(storageStatsProvider);

    final retentionDays = settings?.retentionDays ?? 7;
    final telemetryEnabled = settings?.telemetryEnabled ?? true;
    final maxStorageMb = settings?.maxStorageMb ?? 25;

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Settings',
              subtitle: 'AI, telemetry retention, storage quotas, and tools.',
            ),
            const SectionLabel(label: 'AI Engine & Privacy'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  const _SettingsTile(
                    icon: Icons.psychology_outlined,
                    title: 'Ghost AI Engine',
                    subtitle: 'On-device hybrid analysis pipeline (Active)',
                  ),
                  const Divider(height: 1, indent: 56),
                  SwitchListTile(
                    secondary: const ScopeIconBox(icon: Icons.shield_outlined, size: ScopeIconBoxSize.sm),
                    title: Text('Event & Telemetry Logging', style: theme.textTheme.titleSmall),
                    subtitle: const Text('Local privacy-preserving diagnostic metrics'),
                    value: telemetryEnabled,
                    onChanged: (value) async {
                      try {
                        await controller.updateUserSettings(telemetryEnabled: value);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(value ? 'Telemetry logging enabled' : 'Telemetry logging disabled'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to update telemetry setting')),
                          );
                        }
                      }
                    },
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
            const SectionLabel(label: 'Telemetry Retention & Storage Quotas'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.auto_delete_outlined,
                    title: 'Telemetry Retention Period',
                    subtitle: 'Cutoff: ${_formatRetention(retentionDays)}',
                    onTap: () => _showRetentionPicker(context, retentionDays),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'Storage Quota Limit',
                    subtitle: 'Limit: ${_formatStorageMb(maxStorageMb)}',
                    onTap: () => _showStorageQuotaPicker(context, maxStorageMb),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.storage_rounded,
                    title: 'Storage Quota Status',
                    subtitle: storageStatsAsync.when(
                      data: (stats) =>
                          '${stats.totalNotifications} notifications (~${stats.estimatedSizeMb} MB used)',
                      loading: () => 'Calculating database storage...',
                      error: (err, _) => 'Storage info unavailable',
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.cleaning_services_outlined,
                    title: 'Run Storage Cleanup',
                    subtitle: 'Purge items exceeding retention and quota limits',
                    onTap: () async {
                      await controller.runBackgroundCleanup();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Storage quota cleanup executed'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
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

  void _showRetentionPicker(BuildContext context, int currentDays) {
    showDialog(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Select Retention Period'),
        children: [
          _buildOption(dialogCtx, '3 Days', 3, currentDays),
          _buildOption(dialogCtx, '7 Days', 7, currentDays),
          _buildOption(dialogCtx, '14 Days', 14, currentDays),
          _buildOption(dialogCtx, '30 Days', 30, currentDays),
          _buildOption(dialogCtx, 'Unlimited (Keep all)', -1, currentDays),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext dialogCtx, String label, int days, int currentDays) {
    return SimpleDialogOption(
      onPressed: () async {
        Navigator.of(dialogCtx).pop();
        try {
          await controller.updateUserSettings(retentionDays: days);
          if (dialogCtx.mounted) {
            ScaffoldMessenger.of(dialogCtx).showSnackBar(
              SnackBar(content: Text('Retention set to $label')),
            );
          }
        } catch (_) {
          if (dialogCtx.mounted) {
            ScaffoldMessenger.of(dialogCtx).showSnackBar(
              const SnackBar(content: Text('Failed to update retention setting')),
            );
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(
              days == currentDays ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: Theme.of(dialogCtx).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(label),
          ],
        ),
      ),
    );
  }

  void _showStorageQuotaPicker(BuildContext context, int currentMb) {
    showDialog(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Select Storage Quota Ceiling'),
        children: [
          _buildQuotaOption(dialogCtx, '10 MB', 10, currentMb),
          _buildQuotaOption(dialogCtx, '25 MB (Default)', 25, currentMb),
          _buildQuotaOption(dialogCtx, '50 MB', 50, currentMb),
          _buildQuotaOption(dialogCtx, '100 MB', 100, currentMb),
          _buildQuotaOption(dialogCtx, 'Unlimited', -1, currentMb),
        ],
      ),
    );
  }

  Widget _buildQuotaOption(BuildContext dialogCtx, String label, int mb, int currentMb) {
    return SimpleDialogOption(
      onPressed: () async {
        Navigator.of(dialogCtx).pop();
        try {
          await controller.updateUserSettings(maxStorageMb: mb);
          if (dialogCtx.mounted) {
            ScaffoldMessenger.of(dialogCtx).showSnackBar(
              SnackBar(content: Text('Storage quota set to $label')),
            );
          }
        } catch (_) {
          if (dialogCtx.mounted) {
            ScaffoldMessenger.of(dialogCtx).showSnackBar(
              const SnackBar(content: Text('Failed to update storage quota setting')),
            );
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(
              mb == currentMb ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: Theme.of(dialogCtx).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(label),
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
