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
                    icon: Icons.lock_clock_outlined,
                    title: 'Federated Learning Audit Log',
                    subtitle: 'DP-FedAvg active (ε = ${controller.flManager.cumulativeEpsilonSpent.toStringAsFixed(2)})',
                    onTap: () => _showAuditLogModal(context, controller),
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
  }

  void _showAuditLogModal(BuildContext context, NotificationController controller) {
    final flManager = controller.flManager;
    final logs = flManager.auditLogs.reversed.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Federated Learning Audit Log',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Text(
                  'Privacy Budget Spent (ε): ${flManager.cumulativeEpsilonSpent.toStringAsFixed(4)} / ${flManager.dp.config.maxPrivacyBudgetEpsilon}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: AppSpacing.md),
                if (logs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: Text(
                        'No local federated learning rounds recorded yet.\nSubmit AI Playground feedback to trigger local DP training.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: logs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final isSuccess = log.status == 'success';
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isSuccess ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                            color: isSuccess ? Colors.green : Colors.amber,
                          ),
                          title: Text('Round: ${log.roundId} [${log.status}]'),
                          subtitle: Text(
                            '${log.details}\nSamples: ${log.sampleCount} | Norm: ${log.initialGradientNorm.toStringAsFixed(2)} -> ${log.clippedGradientNorm.toStringAsFixed(2)} | Noise: ${log.noiseScale.toStringAsFixed(3)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
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
