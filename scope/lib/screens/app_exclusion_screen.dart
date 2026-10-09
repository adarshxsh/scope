import 'package:flutter/material.dart';
import 'package:scope/core/services/app_exclusion_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Screen for managing app exclusion controls to filter out specific apps from notification ingestion.
class AppExclusionScreen extends StatefulWidget {
  final NotificationController controller;

  const AppExclusionScreen({super.key, required this.controller});

  @override
  State<AppExclusionScreen> createState() => _AppExclusionScreenState();
}

class _AppExclusionScreenState extends State<AppExclusionScreen> {
  final TextEditingController _packageController = TextEditingController();

  @override
  void dispose() {
    _packageController.dispose();
    super.dispose();
  }

  void _addPackage() {
    final pkg = _packageController.text.trim();
    if (pkg.isNotEmpty) {
      widget.controller.exclusionService.addExcludedPackage(pkg);
      _packageController.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = widget.controller.exclusionService;
    final excludedList = service.excludedPackages.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Exclusion Controls'),
        elevation: 0,
      ),
      body: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'App Exclusion Controls',
              subtitle: 'Prevent notifications from specific apps from being ingested or analyzed.',
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Add custom package form
            ScopeSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exclude an App by Package Name',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _packageController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. com.whatsapp',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          ),
                          onSubmitted: (_) => _addPackage(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ElevatedButton(
                        onPressed: _addPackage,
                        child: const Text('Exclude'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Quick exclude suggestions
            const SectionLabel(label: 'Quick Exclusion Presets'),
            const SizedBox(height: AppSpacing.sm),
            ScopeSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: AppExclusionService.popularAppsToExclude.map((app) {
                  final name = app['name']!;
                  final pkg = app['package']!;
                  final isExcluded = service.isPackageExcluded(pkg);

                  return ListTile(
                    title: Text(name),
                    subtitle: Text(pkg, style: theme.textTheme.bodySmall),
                    trailing: Switch(
                      value: isExcluded,
                      onChanged: (val) {
                        service.togglePackageExcluded(pkg);
                        setState(() {});
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Excluded Apps List
            SectionLabel(label: 'Excluded Package List (${excludedList.length})'),
            const SizedBox(height: AppSpacing.sm),
            if (excludedList.isEmpty)
              ScopeSurface(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'No custom app package exclusions configured.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted(context)),
                    ),
                  ),
                ),
              )
            else
              ScopeSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: excludedList.map((pkg) {
                    return ListTile(
                      title: Text(pkg, style: theme.textTheme.bodyMedium),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.critical),
                        onPressed: () {
                          service.removeExcludedPackage(pkg);
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
    );
  }
}
