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
                  subtitle: 'AI, privacy, and storage governance.',
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
                        icon: Icons.notifications_active_outlined,
                        title: 'Notification Access',
                        subtitle: controller.isListenerEnabled ? 'Enabled' : 'Not enabled',
                        onTap: controller.openNotificationSettings,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                const SectionLabel(label: 'Privacy & Governance'),
                const SizedBox(height: AppSpacing.md),
                ScopeSurface(
                  padding: EdgeInsets.zero,
                  elevated: false,
                  child: Column(
                    children: [
                      _SettingsDropdownTile<int>(
                        icon: Icons.auto_delete_outlined,
                        title: 'Retention Period',
                        subtitle: 'Purge notifications older than cutoff',
                        value: controller.retentionDays,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 Day')),
                          DropdownMenuItem(value: 3, child: Text('3 Days')),
                          DropdownMenuItem(value: 7, child: Text('7 Days')),
                          DropdownMenuItem(value: 14, child: Text('14 Days')),
                          DropdownMenuItem(value: 30, child: Text('30 Days')),
                        ],
                        onChanged: (val) {
                          if (val != null) controller.setRetentionDays(val);
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsSwitchTile(
                        icon: Icons.analytics_outlined,
                        title: 'Telemetry Event Logging',
                        subtitle: controller.telemetryLoggingEnabled
                            ? 'Logging local analysis events'
                            : 'Event logging disabled',
                        value: controller.telemetryLoggingEnabled,
                        onChanged: (val) => controller.setTelemetryLoggingEnabled(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsDropdownTile<int>(
                        icon: Icons.data_usage_outlined,
                        title: 'Storage Quota Cap',
                        subtitle: 'Maximum local notification count limit',
                        value: controller.storageQuotaCap,
                        items: const [
                          DropdownMenuItem(value: 100, child: Text('100 records')),
                          DropdownMenuItem(value: 250, child: Text('250 records')),
                          DropdownMenuItem(value: 500, child: Text('500 records')),
                          DropdownMenuItem(value: 1000, child: Text('1,000 records')),
                          DropdownMenuItem(value: 5000, child: Text('5,000 records')),
                          DropdownMenuItem(value: 0, child: Text('Unlimited')),
                        ],
                        onChanged: (val) {
                          if (val != null) controller.setStorageQuotaCap(val);
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

class _SettingsDropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _SettingsDropdownTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ScopeIconBox(icon: icon, size: ScopeIconBoxSize.sm),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: theme.colorScheme.surface,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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

    return ListTile(
      leading: ScopeIconBox(icon: icon, size: ScopeIconBoxSize.sm),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
