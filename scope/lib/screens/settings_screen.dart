import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/widgets/scope_card.dart';

/// Settings for AI, privacy, and developer tools.
class SettingsScreen extends StatelessWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Settings', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 24),
          ScopeCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.psychology_outlined,
                  title: 'Ghost AI Engine',
                  subtitle: 'On-device hybrid analysis pipeline',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Privacy',
                  subtitle: 'All analysis runs on your device',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification Access',
                  subtitle: controller.isListenerEnabled ? 'Enabled' : 'Not enabled',
                  onTap: controller.openNotificationSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Developer', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ScopeCard(
            padding: EdgeInsets.zero,
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
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.analytics_outlined,
                  title: 'Diagnostics',
                  subtitle: 'Pipeline trace and templates',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DiagnosticScreen(engine: controller.engine),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.refresh,
                  title: 'Refresh Notifications',
                  subtitle: 'Pull latest from device',
                  onTap: controller.refresh,
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.delete_outline,
                  title: 'Clear All Data',
                  subtitle: 'Remove stored notifications',
                  onTap: controller.clearAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Scope · AttentionOS\nOn-device notification intelligence.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
