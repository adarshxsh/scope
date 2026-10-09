import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Dedicated Management UI Screen for Package & Category Exclusions.
class AppExclusionScreen extends StatefulWidget {
  final NotificationController controller;

  const AppExclusionScreen({super.key, required this.controller});

  @override
  State<AppExclusionScreen> createState() => _AppExclusionScreenState();
}

class _AppExclusionScreenState extends State<AppExclusionScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategoryFilter = 'all'; // 'all', 'banking', 'otp', 'health', 'excluded'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'banking':
        return Icons.account_balance_outlined;
      case 'otp':
        return Icons.shield_outlined;
      case 'health':
        return Icons.health_and_safety_outlined;
      default:
        return Icons.apps_outlined;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'banking':
        return AppColors.high;
      case 'otp':
        return AppColors.medium;
      case 'health':
        return AppColors.complete;
      default:
        return AppColors.low;
    }
  }

  String _getCategoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'banking':
        return 'Banking & Finance';
      case 'otp':
        return 'OTP & 2FA';
      case 'health':
        return 'Healthcare';
      default:
        return 'General';
    }
  }

  Widget _buildFilterChip(String label, IconData icon, String filterKey) {
    final selected = _selectedCategoryFilter == filterKey;

    return FilterChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? AppColors.onSurface : AppColors.low,
      ),
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.surfaceHigh,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        color: selected ? AppColors.onSurface : AppColors.low,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.borderStrong : AppColors.border,
        ),
      ),
      onSelected: (_) {
        setState(() => _selectedCategoryFilter = filterKey);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = widget.controller.exclusionManager;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final allApps = manager.getAllKnownApps(notifications: widget.controller.notifications);
        final query = _searchController.text.toLowerCase().trim();

        // Apply search and category filters
        final filteredApps = allApps.where((app) {
          final matchesQuery = query.isEmpty ||
              app.appName.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);

          if (!matchesQuery) return false;

          switch (_selectedCategoryFilter) {
            case 'banking':
              return app.category == 'banking';
            case 'otp':
              return app.category == 'otp';
            case 'health':
              return app.category == 'health';
            case 'excluded':
              return app.isExcluded;
            case 'included':
              return !app.isExcluded;
            default:
              return true;
          }
        }).toList();

        final excludedCount = allApps.where((a) => a.isExcluded).length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('App Exclusion Manager'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Reset'),
                onPressed: () async {
                  await manager.resetToDefaults();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Exclusions reset to defaults'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          body: ScopeScreenBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Privacy Guardrails',
                  subtitle: '$excludedCount application${excludedCount == 1 ? '' : 's'} excluded from local storage capture.',
                ),
                // Search Input Field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by app name or package...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),

                // Category Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All (${allApps.length})', Icons.apps_outlined, 'all'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Banking', Icons.account_balance_outlined, 'banking'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('OTP / 2FA', Icons.shield_outlined, 'otp'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Health', Icons.health_and_safety_outlined, 'health'),
                      const SizedBox(width: AppSpacing.xs),
                      _buildFilterChip('Excluded ($excludedCount)', Icons.block_outlined, 'excluded'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Applications List
                Expanded(
                  child: filteredApps.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded, size: 48, color: AppColors.low),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'No applications found',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Try adjusting your search query or filter chips.',
                                  style: theme.textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          itemCount: filteredApps.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (context, index) {
                            final app = filteredApps[index];
                            final categoryColor = _getCategoryColor(app.category);

                            return ScopeSurface(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              elevated: false,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ScopeIconBox(
                                  icon: _getCategoryIcon(app.category),
                                  size: ScopeIconBoxSize.md,
                                  background: categoryColor.withValues(alpha: 0.12),
                                  color: categoryColor,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        app.appName,
                                        style: theme.textTheme.titleSmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (app.isDefaultSensitive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: categoryColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _getCategoryLabel(app.category),
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: categoryColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  app.packageName,
                                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      app.isExcluded ? 'Blocked' : 'Allowed',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: app.isExcluded ? AppColors.critical : AppColors.complete,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Switch.adaptive(
                                      value: app.isExcluded,
                                      activeTrackColor: AppColors.critical,
                                      onChanged: (bool newValue) async {
                                        await manager.setExclusion(
                                          app.packageName,
                                          newValue,
                                          appName: app.appName,
                                          category: app.category,
                                        );
                                      },
                                    ),
                                  ],
                                ),
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
