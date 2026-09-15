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

/// Settings for AI, privacy, and developer tools.
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
                const SectionLabel(label: 'Retention & Telemetry'),
                const SizedBox(height: AppSpacing.md),
                ScopeSurface(
                  padding: EdgeInsets.zero,
                  elevated: false,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const ScopeIconBox(icon: Icons.history_outlined, size: ScopeIconBoxSize.sm),
                        title: Text('Retention Duration', style: theme.textTheme.titleSmall),
                        subtitle: Text('${controller.retentionDays} Days retention window'),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            key: const Key('retention_dropdown'),
                            value: controller.retentionDays,
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('3 Days')),
                              DropdownMenuItem(value: 7, child: Text('7 Days')),
                              DropdownMenuItem(value: 14, child: Text('14 Days')),
                              DropdownMenuItem(value: 30, child: Text('30 Days')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                controller.setRetentionDays(val);
                              }
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        key: const Key('telemetry_switch'),
                        secondary: const ScopeIconBox(icon: Icons.analytics_outlined, size: ScopeIconBoxSize.sm),
                        title: Text('Telemetry Collection', style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          controller.telemetryEnabled ? 'Enabled' : 'Disabled',
                        ),
                        value: controller.telemetryEnabled,
                        onChanged: (val) {
                          controller.setTelemetryEnabled(val);
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
