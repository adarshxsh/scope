import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Interactive UI for managing native pre-queue app exclusions & system category filters.
class AppExclusionScreen extends StatefulWidget {
  final NotificationController controller;

  const AppExclusionScreen({super.key, required this.controller});

  @override
  State<AppExclusionScreen> createState() => _AppExclusionScreenState();
}

class _AppExclusionScreenState extends State<AppExclusionScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.loadExclusionSettings();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final apps = controller.installedApps;

    final filteredApps = apps.where((app) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return app.appName.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Exclusion Controls'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'App Exclusion Controls',
              subtitle: 'Exclude sensitive apps and system noise before ingestion.',
            ),
            const SizedBox(height: AppSpacing.md),
            // System Category Exclusion Card
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              elevated: false,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const ScopeIconBox(
                  icon: Icons.subtitles_off_outlined,
                  size: ScopeIconBoxSize.sm,
                ),
                title: Text(
                  'Exclude System Status & Media Notifications',
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: const Text(
                  'Drops ongoing status, navigation, media, and progress notifications at the native service boundary.',
                ),
                value: controller.excludeSystemCategories,
                onChanged: (value) {
                  controller.setExcludeSystemCategories(value);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            // Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search installed applications...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel(label: 'Installed Applications'),
            const SizedBox(height: AppSpacing.sm),
            if (filteredApps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: Text(
                    'No installed applications match your search.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ScopeSurface(
                padding: EdgeInsets.zero,
                elevated: false,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredApps.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 56),
                  itemBuilder: (context, index) {
                    final app = filteredApps[index];
                    final isExcluded = controller.isPackageExcluded(app.packageName);
                    return SwitchListTile(
                      secondary: ScopeIconBox(
                        icon: isExcluded ? Icons.block : Icons.apps,
                        size: ScopeIconBoxSize.sm,
                      ),
                      title: Text(app.appName, style: theme.textTheme.titleSmall),
                      subtitle: Text(
                        '${app.packageName}${isExcluded ? " • Excluded" : ""}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isExcluded ? theme.colorScheme.error : null,
                        ),
                      ),
                      value: !isExcluded,
                      onChanged: (enabled) {
                        controller.setPackageExcluded(app.packageName, !enabled);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
