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

/// Settings for AI, privacy, telemetry retention, storage quota, and developer tools.
class SettingsScreen extends StatefulWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.loadUserSettings();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  String _formatRetention(int days) {
    if (days <= 0 || days == -1) return 'Unlimited';
    return '$days Days';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Settings',
              subtitle: 'AI, privacy, telemetry, and storage quota controls.',
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
            const SectionLabel(label: 'Privacy & Telemetry'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const ScopeIconBox(
                      icon: Icons.history_toggle_off_rounded,
                      size: ScopeIconBoxSize.sm,
                    ),
                    title: Text('Event Logging & Telemetry', style: theme.textTheme.titleSmall),
                    subtitle: const Text('Log local execution traces (zero PII)'),
                    value: controller.telemetryEnabled,
                    onChanged: (enabled) async {
                      await controller.updateUserSettings(telemetryEnabled: enabled);
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.timer_outlined,
                    title: 'Telemetry Retention Period',
                    subtitle: 'Current: ${_formatRetention(controller.retentionDays)}',
                    onTap: () => _showRetentionDialog(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.cleaning_services_outlined,
                    title: 'Clear Telemetry Logs',
                    subtitle: 'Purge stored local telemetry events',
                    onTap: () async {
                      await controller.clearTelemetryLogs();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Telemetry logs cleared'),
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
            const SectionLabel(label: 'Storage Governance'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.sd_storage_outlined,
                    title: 'Storage Quota Limit',
                    subtitle: '${controller.storageQuotaMb} MB ceiling (Row cap: ${controller.maxRowCap})',
                    onTap: () => _showQuotaDialog(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.compress_rounded,
                    title: 'Enforce Quota & Trim Storage',
                    subtitle: 'Evict old records to stay under limits',
                    onTap: () async {
                      await controller.enforceStorageQuota();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Storage quota enforced and trimmed'),
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

  void _showRetentionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Select Telemetry Retention'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(retentionDays: 3);
                Navigator.pop(dialogContext);
              },
              child: const Text('3 Days'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(retentionDays: 7);
                Navigator.pop(dialogContext);
              },
              child: const Text('7 Days'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(retentionDays: 14);
                Navigator.pop(dialogContext);
              },
              child: const Text('14 Days'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(retentionDays: 30);
                Navigator.pop(dialogContext);
              },
              child: const Text('30 Days'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(retentionDays: -1);
                Navigator.pop(dialogContext);
              },
              child: const Text('Unlimited'),
            ),
          ],
        );
      },
    );
  }

  void _showQuotaDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Select Storage Quota Ceiling'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(storageQuotaMb: 10, maxRowCap: 2000);
                Navigator.pop(dialogContext);
              },
              child: const Text('10 MB (2,000 items)'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(storageQuotaMb: 25, maxRowCap: 5000);
                Navigator.pop(dialogContext);
              },
              child: const Text('25 MB (5,000 items)'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(storageQuotaMb: 50, maxRowCap: 10000);
                Navigator.pop(dialogContext);
              },
              child: const Text('50 MB (10,000 items)'),
            ),
            SimpleDialogOption(
              onPressed: () {
                widget.controller.updateUserSettings(storageQuotaMb: 100, maxRowCap: 20000);
                Navigator.pop(dialogContext);
              },
              child: const Text('100 MB (20,000 items)'),
            ),
          ],
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
