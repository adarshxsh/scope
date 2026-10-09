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

/// Settings for AI, privacy, storage governance, and developer tools.
class SettingsScreen extends StatelessWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ScopeScreenBody(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                const SectionHeader(
                  title: 'Settings',
                  subtitle: 'AI, privacy, storage governance, and developer tools.',
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
                      ListTile(
                        leading: const ScopeIconBox(
                          icon: Icons.graphic_eq_rounded,
                          size: ScopeIconBoxSize.sm,
                        ),
                        title: Text('Telemetry Logging', style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          controller.telemetryEnabled
                              ? 'Enabled — local model metrics collection'
                              : 'Disabled — no telemetry logged',
                        ),
                        trailing: Switch(
                          key: const Key('telemetry_switch'),
                          value: controller.telemetryEnabled,
                          onChanged: (val) => controller.setTelemetryEnabled(val),
                        ),
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
                const SectionLabel(label: 'Storage & Retention Governance'),
                const SizedBox(height: AppSpacing.md),
                // Live Storage Statistics Card
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  elevated: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live Storage Statistics', style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatColumn(
                            label: 'Records',
                            value: '${controller.totalStoredCount}',
                          ),
                          _StatColumn(
                            label: 'Est. DB Size',
                            value: controller.estimatedDbSizeString,
                          ),
                          _StatColumn(
                            label: 'Retention',
                            value: controller.retentionDays == 0
                                ? 'Unlimited'
                                : '${controller.retentionDays}d',
                          ),
                          _StatColumn(
                            label: 'Quota',
                            value: controller.maxNotificationQuota == 0
                                ? 'Unlimited'
                                : '${controller.maxNotificationQuota}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ScopeSurface(
                  padding: EdgeInsets.zero,
                  elevated: false,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const ScopeIconBox(
                          icon: Icons.auto_delete_outlined,
                          size: ScopeIconBoxSize.sm,
                        ),
                        title: Text('Retention Window', style: theme.textTheme.titleSmall),
                        subtitle: Text(_retentionSubtitle(controller.retentionDays)),
                        trailing: DropdownButton<int>(
                          key: const Key('retention_dropdown'),
                          value: controller.retentionDays,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 Days')),
                            DropdownMenuItem(value: 7, child: Text('7 Days')),
                            DropdownMenuItem(value: 14, child: Text('14 Days')),
                            DropdownMenuItem(value: 30, child: Text('30 Days')),
                            DropdownMenuItem(value: 0, child: Text('Unlimited')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              controller.setRetentionDays(val);
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const ScopeIconBox(
                          icon: Icons.storage_outlined,
                          size: ScopeIconBoxSize.sm,
                        ),
                        title: Text('Storage Quota Limit', style: theme.textTheme.titleSmall),
                        subtitle: Text(_quotaSubtitle(controller.maxNotificationQuota)),
                        trailing: DropdownButton<int>(
                          key: const Key('quota_dropdown'),
                          value: controller.maxNotificationQuota,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 250, child: Text('250 Items')),
                            DropdownMenuItem(value: 500, child: Text('500 Items')),
                            DropdownMenuItem(value: 1000, child: Text('1,000 Items')),
                            DropdownMenuItem(value: 2500, child: Text('2,500 Items')),
                            DropdownMenuItem(value: 0, child: Text('Unlimited')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              controller.setMaxNotificationQuota(val);
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        key: const Key('purge_data_tile'),
                        icon: Icons.cleaning_services_outlined,
                        title: 'Purge Expired Data Now',
                        subtitle: 'Enforce retention window and quota limit immediately',
                        onTap: () async {
                          final purged = await controller.purgeExpiredDataNow();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  purged > 0
                                      ? 'Storage cleanup complete: $purged item(s) purged'
                                      : 'Storage cleanup complete: No items to purge',
                                ),
                                duration: const Duration(seconds: 2),
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
            );
          },
        ),
      ),
    );
  }

  String _retentionSubtitle(int days) {
    if (days == 0) return 'Keep records indefinitely';
    return 'Delete records older than $days days';
  }

  String _quotaSubtitle(int quota) {
    if (quota == 0) return 'Unlimited database capacity';
    return 'FIFO eviction when records exceed $quota';
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    super.key,
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
