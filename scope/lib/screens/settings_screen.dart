import 'package:flutter/material.dart';
import 'package:scope/core/privacy/ingestion_guardrail_controller.dart';
import 'package:scope/core/privacy/ingestion_policy.dart';
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
                    icon: Icons.notifications_active_outlined,
                    title: 'Notification Access',
                    subtitle: controller.isListenerEnabled ? 'Enabled' : 'Not enabled',
                    onTap: controller.openNotificationSettings,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            const SectionLabel(label: 'Privacy & Ingestion Guardrails'),
            const SizedBox(height: AppSpacing.md),
            _PrivacyGuardrailsPanel(
              guardrailController: controller.guardrailController,
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
                    subtitle: 'Generate analyzed notifications',
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

class _PrivacyGuardrailsPanel extends StatelessWidget {
  final IngestionGuardrailController guardrailController;

  const _PrivacyGuardrailsPanel({required this.guardrailController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: guardrailController,
      builder: (context, _) {
        final policy = guardrailController.policy;
        final blockedPackages = policy.blockedPackages;
        final excludedCategories = policy.excludedCategories;

        final presetApps = [
          {'name': 'WhatsApp', 'package': 'com.whatsapp'},
          {'name': 'Telegram', 'package': 'org.telegram.messenger'},
          {'name': 'Instagram', 'package': 'com.instagram.android'},
          {'name': 'Paytm / Banking', 'package': 'net.one97.paytm'},
          {'name': 'Amazon Shopping', 'package': 'in.amazon.mShop.android.shopping'},
        ];

        return ScopeSurface(
          padding: const EdgeInsets.all(AppSpacing.md),
          elevated: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Category Exclusions',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Notifications in excluded categories are dropped prior to database commit.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exclude Finance'),
                subtitle: const Text('Bank alerts, transaction updates'),
                value: excludedCategories.any((c) => c.toLowerCase() == 'finance'),
                onChanged: (_) => guardrailController.toggleCategoryExclusion('finance'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exclude Health'),
                subtitle: const Text('Medical appointments, health alerts'),
                value: excludedCategories.any((c) => c.toLowerCase() == 'health'),
                onChanged: (_) => guardrailController.toggleCategoryExclusion('health'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exclude Social'),
                subtitle: const Text('Likes, comments, social updates'),
                value: excludedCategories.any((c) => c.toLowerCase() == 'social'),
                onChanged: (_) => guardrailController.toggleCategoryExclusion('social'),
              ),
              const Divider(height: AppSpacing.lg),
              Text(
                'Sensitive Controls',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('OTP Masking'),
                subtitle: const Text('Redact OTP codes before local storage'),
                value: policy.otpMaskingEnabled,
                onChanged: (val) => guardrailController.setOtpMasking(val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Financial Protection Mode'),
                subtitle: const Text('Block all sensitive banking and OTP content'),
                value: policy.financialProtectionEnabled,
                onChanged: (val) => guardrailController.setFinancialProtection(val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Block System Noise'),
                subtitle: const Text('Drop ongoing alerts and status updates'),
                value: policy.blockSystemNoise,
                onChanged: (val) => guardrailController.setBlockSystemNoise(val),
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'App Blocklist',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Package'),
                    onPressed: () => _showAddPackageDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Blocked packages are discarded in volatile memory.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...presetApps.map((app) {
                final pkg = app['package']!;
                final name = app['name']!;
                final isBlocked = blockedPackages.any((p) => p.toLowerCase() == pkg.toLowerCase());
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name),
                  subtitle: Text(pkg),
                  value: isBlocked,
                  onChanged: (_) => guardrailController.togglePackageBlock(pkg),
                );
              }),
              if (blockedPackages.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Custom Blocked Packages:',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  children: blockedPackages.map((pkg) {
                    return Chip(
                      label: Text(pkg, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => guardrailController.togglePackageBlock(pkg),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showAddPackageDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Block App Package'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e.g. com.example.sensitiveapp',
              labelText: 'Package Name ID',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final pkg = controller.text.trim();
                if (pkg.isNotEmpty) {
                  guardrailController.togglePackageBlock(pkg);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Block'),
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

