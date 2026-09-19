import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Screen for managing notification ingestion privacy guardrails,
/// app package blacklists, sensitive category auto-exclusions, and sanitization.
class NotificationPrivacyScreen extends StatefulWidget {
  final NotificationController controller;

  const NotificationPrivacyScreen({super.key, required this.controller});

  @override
  State<NotificationPrivacyScreen> createState() => _NotificationPrivacyScreenState();
}

class _NotificationPrivacyScreenState extends State<NotificationPrivacyScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _installedApps = [];
  List<Map<String, String>> _filteredApps = [];
  bool _isLoadingApps = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterApps);
    _loadInstalledApps();
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterApps);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    final apps = await widget.controller.getInstalledApps();
    if (mounted) {
      setState(() {
        _installedApps = apps;
        _filteredApps = apps;
        _isLoadingApps = false;
      });
    }
  }

  void _filterApps() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_installedApps);
      } else {
        _filteredApps = _installedApps.where((app) {
          final name = (app['appName'] ?? '').toLowerCase();
          final pkg = (app['packageName'] ?? '').toLowerCase();
          return name.contains(query) || pkg.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final privacy = widget.controller.privacyEngine;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Privacy'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Ingestion Guardrails',
              subtitle: 'Control package blacklists and sensitive category exclusions.',
            ),
            const SectionLabel(label: 'Sensitive Categories'),
            const SizedBox(height: AppSpacing.sm),
            ScopeSurface(
              padding: EdgeInsets.zero,
              elevated: false,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      'Exclude Sensitive Categories (OTPs & Health)',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: const Text(
                      'Automatically drop two-factor authentication codes, OTPs, and healthcare alerts before local storage.',
                    ),
                    value: privacy.excludeOtpAndHealth,
                    onChanged: (val) async {
                      await widget.controller.setSensitiveCategoryExclusion(
                        excludeOtpAndHealth: val,
                      );
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: Text(
                      'Exclude Financial Notifications',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: const Text(
                      'Automatically drop banking, wallet, and transaction updates prior to storage.',
                    ),
                    value: privacy.excludeFinance,
                    onChanged: (val) async {
                      await widget.controller.setSensitiveCategoryExclusion(
                        excludeFinance: val,
                      );
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: Text(
                      'Field-Level Sanitization',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: const Text(
                      'Mask numerical verification codes and monetary amounts in allowed notifications.',
                    ),
                    value: privacy.fieldSanitizationEnabled,
                    onChanged: (val) {
                      widget.controller.toggleFieldSanitization(val);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            const SectionLabel(label: 'App Package Blacklist'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search installed applications...',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isLoadingApps)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_filteredApps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'No matching applications found.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ScopeSurface(
                padding: EdgeInsets.zero,
                elevated: false,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredApps.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final app = _filteredApps[index];
                    final appName = app['appName'] ?? 'Unknown App';
                    final pkgName = app['packageName'] ?? 'unknown';
                    final isIngestionEnabled =
                        !widget.controller.isPackageBlacklisted(pkgName);

                    return SwitchListTile(
                      key: ValueKey('app_tile_$pkgName'),
                      title: Text(appName, style: theme.textTheme.titleSmall),
                      subtitle: Text(
                        pkgName,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                      ),
                      value: isIngestionEnabled,
                      onChanged: (enabled) async {
                        await widget.controller.togglePackageBlacklist(
                          pkgName,
                          enabled,
                        );
                        setState(() {});
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
