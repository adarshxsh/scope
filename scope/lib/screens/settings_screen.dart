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

  void _showPrivacyStorageModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            final theme = Theme.of(context);
            final retentionText = controller.retentionDays == 0
                ? 'Unlimited'
                : '${controller.retentionDays} Days';

            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Privacy & Storage Settings',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Configure telemetry logging, data retention duration, and local database storage caps.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Telemetry Switch Tile
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const ScopeIconBox(icon: Icons.shield_outlined, size: ScopeIconBoxSize.sm),
                      title: Text('Telemetry & Event Logging', style: theme.textTheme.titleSmall),
                      subtitle: const Text('Generate explainability traces and diagnostic event logs.'),
                      value: controller.telemetryEnabled,
                      onChanged: (val) {
                        controller.updateUserSettings(telemetryEnabled: val);
                      },
                    ),
                    const Divider(height: 24),

                    // Retention Duration Dropdown
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const ScopeIconBox(icon: Icons.timer_outlined, size: ScopeIconBoxSize.sm),
                      title: Text('Data Retention Duration', style: theme.textTheme.titleSmall),
                      subtitle: Text('Purge notifications older than $retentionText.'),
                      trailing: DropdownButton<int>(
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
                            controller.updateUserSettings(retentionDays: val);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 24),

                    // Storage Quota Dropdown
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const ScopeIconBox(icon: Icons.storage_outlined, size: ScopeIconBoxSize.sm),
                      title: Text('Maximum Storage Quota Limit', style: theme.textTheme.titleSmall),
                      subtitle: Text('Cap database growth (${controller.storageQuotaLimit} items max).'),
                      trailing: DropdownButton<int>(
                        value: controller.storageQuotaLimit,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 250, child: Text('250 Items')),
                          DropdownMenuItem(value: 500, child: Text('500 Items')),
                          DropdownMenuItem(value: 1000, child: Text('1000 Items')),
                          DropdownMenuItem(value: 2000, child: Text('2000 Items')),
                          DropdownMenuItem(value: 5000, child: Text('5000 Items')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            controller.updateUserSettings(storageQuotaLimit: val);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 24),

                    // Local Storage Status Inspection Box
                    ScopeSurface(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Local Storage Status',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Stored Notifications: ${controller.currentStorageCount} / ${controller.storageQuotaLimit} items',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Database Status: Healthy · Encrypted Local SQLite',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final theme = Theme.of(context);
        final retentionText = controller.retentionDays == 0
            ? 'Unlimited'
            : '${controller.retentionDays} days';

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
                        subtitle: 'Retention: $retentionText · Quota: ${controller.storageQuotaLimit} items',
                        onTap: () => _showPrivacyStorageModal(context),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.shield_outlined,
                        title: 'Privacy',
                        subtitle: controller.telemetryEnabled
                            ? 'Telemetry active · ${controller.currentStorageCount} items stored'
                            : 'Telemetry disabled · ${controller.currentStorageCount} items stored',
                        onTap: () => _showPrivacyStorageModal(context),
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

