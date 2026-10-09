import 'package:flutter/material.dart';
import 'package:scope/core/privacy/guardrails_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_spacing.dart';

import 'package:scope/widgets/primitives/scope_chip.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Screen for managing sensitive category guardrails and per-app package exclusions.
class GuardrailsSettingsScreen extends StatefulWidget {
  final NotificationController controller;

  const GuardrailsSettingsScreen({super.key, required this.controller});

  @override
  State<GuardrailsSettingsScreen> createState() => _GuardrailsSettingsScreenState();
}

class _GuardrailsSettingsScreenState extends State<GuardrailsSettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guardrails = widget.controller.guardrails;
    final allApps = guardrails.getAppList(widget.controller.notifications);

    final filteredApps = allApps.where((app) {
      if (_searchQuery.isEmpty) return true;
      return app.label.toLowerCase().contains(_searchQuery) ||
          app.packageName.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Guardrails'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Privacy Guardrails',
              subtitle: 'Mute sensitive categories or individual apps to prevent ingestion and purge historical storage.',
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel(label: 'Sensitive Category Guardrails'),
            const SizedBox(height: AppSpacing.sm),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  for (int i = 0; i < SensitiveCategory.values.length; i++) ...[
                    _CategoryGuardrailTile(
                      category: SensitiveCategory.values[i],
                      isMuted: guardrails.isCategoryMuted(SensitiveCategory.values[i]),
                      onChanged: (muted) async {
                        await widget.controller.toggleGuardrailCategory(
                          SensitiveCategory.values[i],
                          muted,
                        );
                        if (context.mounted && muted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Muted ${SensitiveCategory.values[i].label} and purged historical records.',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                    if (i < SensitiveCategory.values.length - 1)
                      const Divider(height: 1, indent: 56),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            const SectionLabel(label: 'Per-App Exclusion Settings'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search app name or package...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (filteredApps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: Text(
                    'No apps found matching "$_searchQuery"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              )
            else
              ScopeSurface(
                padding: EdgeInsets.zero,
                elevated: false,
                child: Column(
                  children: [
                    for (int i = 0; i < filteredApps.length; i++) ...[
                      _AppExclusionTile(
                        appInfo: filteredApps[i],
                        onChanged: (excluded) async {
                          await widget.controller.toggleGuardrailPackage(
                            filteredApps[i].packageName,
                            excluded,
                          );
                          if (context.mounted && excluded) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Excluded ${filteredApps[i].label} and purged historical records.',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      if (i < filteredApps.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryGuardrailTile extends StatelessWidget {
  final SensitiveCategory category;
  final bool isMuted;
  final ValueChanged<bool> onChanged;

  const _CategoryGuardrailTile({
    required this.category,
    required this.isMuted,
    required this.onChanged,
  });

  IconData get _icon {
    switch (category) {
      case SensitiveCategory.bankingOtp:
        return Icons.account_balance_outlined;
      case SensitiveCategory.health:
        return Icons.health_and_safety_outlined;
      case SensitiveCategory.messaging:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SwitchListTile(
      secondary: ScopeIconBox(icon: _icon, size: ScopeIconBoxSize.sm),
      title: Row(
        children: [
          Expanded(
            child: Text(category.label, style: theme.textTheme.titleSmall),
          ),
          if (isMuted)
            const ScopeChip(
              label: 'MUTED',
              icon: Icons.visibility_off_outlined,
              selected: true,
              tone: ScopeChipTone.accent,
            ),

        ],
      ),
      subtitle: Text(category.description),
      value: !isMuted, // Active ingestion = true; Muted = false
      onChanged: (active) => onChanged(!active),
    );
  }
}

class _AppExclusionTile extends StatelessWidget {
  final AppPackageInfo appInfo;
  final ValueChanged<bool> onChanged;

  const _AppExclusionTile({
    required this.appInfo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SwitchListTile(
      secondary: ScopeIconBox(
        icon: appInfo.isExcluded ? Icons.block_rounded : Icons.apps_rounded,
        size: ScopeIconBoxSize.sm,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(appInfo.label, style: theme.textTheme.titleSmall),
          ),
          if (appInfo.isExcluded)
            const ScopeChip(
              label: 'EXCLUDED',
              icon: Icons.block_rounded,
              selected: true,
              tone: ScopeChipTone.accent,
            ),

        ],
      ),
      subtitle: Text(
        appInfo.packageName,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
      value: !appInfo.isExcluded, // Active ingestion = true; Excluded = false
      onChanged: (active) => onChanged(!active),
    );
  }
}
