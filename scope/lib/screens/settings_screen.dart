import 'package:flutter/material.dart';
import 'package:scope/core/analysis/ingestion_guardrail_filter.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/ai_playground_screen.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Settings for AI, privacy, ingestion guardrails, and developer tools.
class SettingsScreen extends StatefulWidget {
  final NotificationController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _packageInputController = TextEditingController();

  @override
  void dispose() {
    _packageInputController.dispose();
    super.dispose();
  }

  void _toggleCategoryExclusion(SensitiveCategory category, bool exclude) {
    final currentConfig = widget.controller.guardrailConfig;
    final updatedCategories = Set<SensitiveCategory>.from(currentConfig.excludedCategories);
    if (exclude) {
      updatedCategories.add(category);
    } else {
      updatedCategories.remove(category);
    }
    final newConfig = currentConfig.copyWith(excludedCategories: updatedCategories);
    widget.controller.updateGuardrailConfig(newConfig);
    setState(() {});
  }

  void _toggleWhitelistMode(bool enabled) {
    final currentConfig = widget.controller.guardrailConfig;
    final newConfig = currentConfig.copyWith(isWhitelistModeEnabled: enabled);
    widget.controller.updateGuardrailConfig(newConfig);
    setState(() {});
  }

  void _showPackageListDialog({required bool isBlacklist}) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final config = widget.controller.guardrailConfig;
            final packageSet = isBlacklist
                ? config.blacklistedPackages
                : config.whitelistedPackages;
            final title = isBlacklist ? 'Blacklisted Packages' : 'Whitelisted Packages';

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _packageInputController,
                      decoration: InputDecoration(
                        labelText: 'Package Name',
                        hintText: 'e.g. com.example.app',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final pkg = _packageInputController.text.trim().toLowerCase();
                            if (pkg.isNotEmpty) {
                              final updatedSet = Set<String>.from(packageSet)..add(pkg);
                              final newConfig = isBlacklist
                                  ? config.copyWith(blacklistedPackages: updatedSet)
                                  : config.copyWith(whitelistedPackages: updatedSet);
                              widget.controller.updateGuardrailConfig(newConfig);
                              _packageInputController.clear();
                              setDialogState(() {});
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (packageSet.isEmpty)
                      const Text('No package filters added yet.',
                          style: TextStyle(fontStyle: FontStyle.italic))
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: packageSet.map((pkg) {
                            return ListTile(
                              dense: true,
                              title: Text(pkg),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () {
                                  final updatedSet = Set<String>.from(packageSet)..remove(pkg);
                                  final newConfig = isBlacklist
                                      ? config.copyWith(blacklistedPackages: updatedSet)
                                      : config.copyWith(whitelistedPackages: updatedSet);
                                  widget.controller.updateGuardrailConfig(newConfig);
                                  setDialogState(() {});
                                  setState(() {});
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = widget.controller.guardrailConfig;
    final telemetry = widget.controller.ingestionTelemetry;

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Settings',
              subtitle: 'AI, privacy, ingestion guardrails, and tools.',
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
                    title: 'Privacy Guarantee',
                    subtitle: 'All data processed locally on-device',
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

            // Ingestion Guardrails Section
            const SectionLabel(label: 'Ingestion Guardrails & Privacy'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              elevated: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: config.isWhitelistModeEnabled,
                    title: Text('Enforce Package Whitelist', style: theme.textTheme.titleSmall),
                    subtitle: const Text('Ingest ONLY from whitelisted packages'),
                    onChanged: _toggleWhitelistMode,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: Text('Package Blacklist (${config.blacklistedPackages.length})',
                        style: theme.textTheme.titleSmall),
                    subtitle: const Text('Explicitly block specific apps prior to ingestion'),
                    onTap: () => _showPackageListDialog(isBlacklist: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.playlist_add_check_rounded),
                    title: Text('Package Whitelist (${config.whitelistedPackages.length})',
                        style: theme.textTheme.titleSmall),
                    subtitle: const Text('Allowed app packages when Whitelist Mode is active'),
                    onTap: () => _showPackageListDialog(isBlacklist: false),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    child: Text('Exclude Sensitive Categories Prior to Ingestion:',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  ...SensitiveCategory.values.map((category) {
                    final isExcluded = config.excludedCategories.contains(category);
                    return SwitchListTile(
                      value: isExcluded,
                      title: Text(category.label, style: theme.textTheme.titleSmall),
                      subtitle: Text(category.description),
                      onChanged: (val) => _toggleCategoryExclusion(category, val),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.sectionGap),

            // Telemetry & Audit Section
            const SectionLabel(label: 'Ingestion Audit & Telemetry'),
            const SizedBox(height: AppSpacing.md),
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              elevated: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pre-Ingestion System Metrics', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Evaluated: ${telemetry.totalEvaluated} | Ingested: ${telemetry.totalIngested}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Excluded (Blacklist): ${telemetry.totalExcludedBlacklist}',
                      style: theme.textTheme.bodySmall),
                  Text('Excluded (Whitelist): ${telemetry.totalExcludedWhitelist}',
                      style: theme.textTheme.bodySmall),
                  Text('Excluded (Sensitive Category): ${telemetry.totalExcludedSensitiveCategory}',
                      style: theme.textTheme.bodySmall),
                  Text('Rejected (Validation): ${telemetry.totalRejectedValidation}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reset Telemetry'),
                      onPressed: () {
                        setState(() {
                          telemetry.reset();
                        });
                      },
                    ),
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
                    subtitle: 'Generate analyzed notifications',
                    onTap: () async {
                      await widget.controller.generateTestData();
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
                    onTap: widget.controller.refresh,
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Clear All Data',
                    subtitle: 'Remove stored notifications',
                    onTap: widget.controller.clearAll,
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
