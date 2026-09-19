import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/preferences/user_preferences.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/ai_playground_screen.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Settings for AI, privacy, data governance, and developer tools.
class SettingsScreen extends ConsumerStatefulWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _storageUsage = 'Calculating...';

  @override
  void initState() {
    super.initState();
    _updateStorageStats();
  }

  Future<void> _updateStorageStats() async {
    final usage = await widget.controller.getFormattedStorageUsage();
    final count = widget.controller.notifications.length;
    if (mounted) {
      setState(() {
        _storageUsage = '$usage ($count stored)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = ref.watch(userPreferencesProvider);
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Settings',
              subtitle: 'Data governance, privacy, and AI tools.',
            ),

            // --- Data & Privacy / Storage Governance Section ---
            const SectionLabel(label: 'Data Governance & Storage'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  // Retention Duration Selector
                  ListTile(
                    leading: const ScopeIconBox(
                      icon: Icons.auto_delete_outlined,
                      size: ScopeIconBoxSize.sm,
                    ),
                    title: Text('Data Retention Duration', style: theme.textTheme.titleSmall),
                    subtitle: Text(prefs.retentionDays == -1
                        ? 'Keep notifications indefinitely'
                        : 'Auto-delete after ${prefs.retentionDays} days'),
                    trailing: DropdownButton<int>(
                      value: prefs.retentionDays,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 Days')),
                        DropdownMenuItem(value: 7, child: Text('7 Days')),
                        DropdownMenuItem(value: 14, child: Text('14 Days')),
                        DropdownMenuItem(value: 30, child: Text('30 Days')),
                        DropdownMenuItem(value: -1, child: Text('Unlimited')),
                      ],
                      onChanged: (val) async {
                        if (val != null) {
                          await prefsNotifier.setRetentionDays(val);
                          await widget.controller.runBackgroundCleanup();
                          await _updateStorageStats();
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1, indent: 56),

                  // Telemetry Logging Toggle
                  SwitchListTile(
                    secondary: const ScopeIconBox(
                      icon: Icons.analytics_outlined,
                      size: ScopeIconBoxSize.sm,
                    ),
                    title: Text('Telemetry & Behavioral Logging', style: theme.textTheme.titleSmall),
                    subtitle: const Text(
                      'Opt-in: Local behavioral logging helps improve AI notification priority predictions. All data remains strictly on-device.',
                    ),
                    value: prefs.telemetryEnabled,
                    onChanged: (val) async {
                      await prefsNotifier.setTelemetryEnabled(val);
                    },
                  ),
                  const Divider(height: 1, indent: 56),

                  // Storage Quota Selector
                  ListTile(
                    leading: const ScopeIconBox(
                      icon: Icons.sd_storage_outlined,
                      size: ScopeIconBoxSize.sm,
                    ),
                    title: Text('Storage Quota Limit', style: theme.textTheme.titleSmall),
                    subtitle: Text(prefs.storageQuotaMb == -1
                        ? 'Unlimited local storage'
                        : 'Max ${prefs.storageQuotaMb} MB local limit'),
                    trailing: DropdownButton<int>(
                      value: prefs.storageQuotaMb,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 50, child: Text('50 MB')),
                        DropdownMenuItem(value: 100, child: Text('100 MB')),
                        DropdownMenuItem(value: 250, child: Text('250 MB')),
                        DropdownMenuItem(value: 500, child: Text('500 MB')),
                        DropdownMenuItem(value: -1, child: Text('Unlimited')),
                      ],
                      onChanged: (val) async {
                        if (val != null) {
                          await prefsNotifier.setStorageQuotaMb(val);
                          await widget.controller.runBackgroundCleanup();
                          await _updateStorageStats();
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1, indent: 56),

                  // Storage Utilization Display
                  ListTile(
                    leading: const ScopeIconBox(
                      icon: Icons.pie_chart_outline,
                      size: ScopeIconBoxSize.sm,
                    ),
                    title: Text('Local Storage Consumed', style: theme.textTheme.titleSmall),
                    subtitle: Text(_storageUsage),
                    trailing: TextButton(
                      onPressed: () async {
                        await widget.controller.runBackgroundCleanup();
                        await _updateStorageStats();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Storage cleanup completed'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text('PURGE NOW'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),

            // --- System & Security Section ---
            const SectionLabel(label: 'System & Security'),
            const SizedBox(height: AppSpacing.md),
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
                    title: 'Privacy Guard',
                    subtitle: 'All analysis runs 100% locally on your device',
                    onTap: null,
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'Notification Access',
                    subtitle: widget.controller.isListenerEnabled ? 'Enabled' : 'Not enabled',
                    onTap: widget.controller.openNotificationSettings,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),

            // --- Developer Section ---
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
                      await widget.controller.generateTestData();
                      await _updateStorageStats();
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
                      AiPlaygroundScreen(controller: widget.controller),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.analytics_outlined,
                    title: 'Diagnostics',
                    subtitle: 'Pipeline trace and templates',
                    onTap: () => ScopeNavigator.push(
                      context,
                      DiagnosticScreen(engine: widget.controller.engine),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.refresh_rounded,
                    title: 'Refresh Notifications',
                    subtitle: 'Pull latest from device',
                    onTap: () async {
                      await widget.controller.refresh();
                      await _updateStorageStats();
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Clear All Data',
                    subtitle: 'Remove stored notifications',
                    onTap: () async {
                      await widget.controller.clearAll();
                      await _updateStorageStats();
                    },
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
