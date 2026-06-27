import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/utils/greeting_util.dart';
import 'package:scope/screens/daily_timeline_screen.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/widgets/action_queue_widget.dart';
import 'package:scope/widgets/daily_brief_card.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/focus_area_card.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_loading.dart';
import 'package:scope/widgets/primitives/scope_progress.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/saved_action_items_widget.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Dashboard home — hierarchy: greeting → brief/CTA → queues → progress → areas.
class HomeScreen extends StatelessWidget {
  final NotificationController controller;
  final void Function(FocusFilterType type, [FocusArea? area]) onStartFocus;

  const HomeScreen({
    super.key,
    required this.controller,
    required this.onStartFocus,
  });

  int _crossAxisCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  double _childAspectRatio(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 1.0;
    if (width < 600) return 1.1;
    return 1.2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = GreetingUtil.greetingFor(DateTime.now());
    final focusCounts = controller.focusAreaCounts;
    final selectedFilter = controller.focusAreaFilter;
    final hasData = controller.notifications.isNotEmpty;

    return SafeArea(
      child: controller.isLoading
          ? const ScopeLoading(message: 'Loading notifications…')
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ScopeScreenBody(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      AppSpacing.screenPadding,
                      AppSpacing.screenPadding,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!controller.isListenerEnabled) ...[
                          _PermissionBanner(controller: controller),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        Text(greeting, style: theme.textTheme.headlineLarge),
                        const SizedBox(height: AppSpacing.lg),
                        DailyBriefCard(
                          reviewedCount: controller.notifications.length,
                          actionCount: controller.actionCountToday,
                          deadlineCount: controller.deadlineCount,
                          financialUpdateCount: controller.financialUpdateCount,
                          estimatedMinutes: controller.estimatedReviewMinutes,
                          canStartFocus: controller.reviewQueue.isNotEmpty,
                          onStartFocus: () => onStartFocus(controller.filterType, selectedFilter),
                          onTapCard: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DailyTimelineScreen(controller: controller),
                              ),
                            );
                          },
                        ),
                        if (controller.savedActionItems.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sectionGap),
                          const SectionLabel(label: 'Today\'s Reminders'),
                          const SizedBox(height: AppSpacing.md),
                          // Use Negative margin to make list edge-to-edge
                          Transform.translate(
                            offset: const Offset(-AppSpacing.screenPadding, 0),
                            child: SizedBox(
                              width: MediaQuery.sizeOf(context).width,
                              child: SavedActionItemsWidget(controller: controller),
                            ),
                          ),
                        ],
                        if (hasData) ...[
                          const SizedBox(height: AppSpacing.sectionGap),
                          const SectionLabel(label: 'Action Queues'),
                          const SizedBox(height: AppSpacing.md),
                          ActionQueueWidget(
                            needsAction: controller.needsAction.length,
                            important: controller.important.length,
                            archived: controller.archivedNotifications.length,
                            onQueueTap: (queue) {
                              switch (queue) {
                                case 'needs':
                                  onStartFocus(FocusFilterType.needsAction);
                                case 'important':
                                  onStartFocus(FocusFilterType.important);
                                case 'archived':
                                  onStartFocus(FocusFilterType.archived);
                              }
                            },
                          ),
                          const SizedBox(height: AppSpacing.sectionGap),
                          ScopeSurface(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionLabel(label: "Today's Progress"),
                                const SizedBox(height: AppSpacing.md),
                                ScopeProgress(
                                  completed: controller.completedToday.length,
                                  total: controller.notifications.length,
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sectionGap),
                        Row(
                          children: [
                            const SectionLabel(label: 'Focus Areas'),
                            if (selectedFilter != null) ...[
                              const Spacer(),
                              TextButton(
                                onPressed: controller.clearFocusAreaFilter,
                                child: const Text('Clear'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ),
                if (!hasData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.notifications_none_outlined,
                      title: "You're all caught up.",
                      message: 'Enable notification access or load test data from Settings.',
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: ScopeScreenBody(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        0,
                        AppSpacing.screenPadding,
                        AppSpacing.xl,
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _crossAxisCount(context),
                          mainAxisSpacing: AppSpacing.sm,
                          crossAxisSpacing: AppSpacing.sm,
                          childAspectRatio: _childAspectRatio(context),
                        ),
                        itemCount: FocusArea.values.length,
                        itemBuilder: (context, index) {
                          final area = FocusArea.values[index];
                          final count = focusCounts[area]!;
                          return FocusAreaCard(
                            area: area,
                            count: count,
                            description: area.descriptionFor(count, controller.notificationsForArea(area)),
                            selected: selectedFilter == area,
                            onTap: () => controller.setFocusAreaFilter(
                              selectedFilter == area ? null : area,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final NotificationController controller;

  const _PermissionBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ScopeSurface(
      borderColor: AppTheme.urgencyColor('high').withValues(alpha: 0.15),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ScopeIconBox(
            icon: Icons.warning_amber_rounded,
            size: ScopeIconBoxSize.sm,
            color: AppTheme.urgencyColor('high'),
            background: AppTheme.urgencyBackground('high'),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Notification access is not enabled.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: controller.openNotificationSettings,
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
