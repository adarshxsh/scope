import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/utils/greeting_util.dart';
import 'package:scope/widgets/action_queue_widget.dart';
import 'package:scope/widgets/daily_brief_card.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/focus_area_card.dart';
import 'package:scope/widgets/progress_widget.dart';
import 'package:scope/widgets/scope_card.dart';

/// Dashboard home — answers "What should I do next?" not "What arrived?"
class HomeScreen extends StatelessWidget {
  final NotificationController controller;
  final void Function([FocusArea? area]) onStartFocus;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = GreetingUtil.greetingFor(DateTime.now());
    final focusCounts = controller.focusAreaCounts;
    final selectedFilter = controller.focusAreaFilter;
    final hasData = controller.notifications.isNotEmpty;

    return SafeArea(
      child: controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!controller.isListenerEnabled) ...[
                          _PermissionBanner(controller: controller),
                          const SizedBox(height: 20),
                        ],
                        Text(greeting, style: theme.textTheme.headlineLarge),
                        const SizedBox(height: 24),
                        DailyBriefCard(
                          reviewedCount: controller.notifications.length,
                          actionCount: controller.actionCountToday,
                          deadlineCount: controller.deadlineCount,
                          financialUpdateCount: controller.financialUpdateCount,
                          estimatedMinutes: controller.estimatedReviewMinutes,
                          canStartFocus: controller.reviewQueue.isNotEmpty,
                          onStartFocus: () => onStartFocus(selectedFilter),
                        ),
                        if (hasData) ...[
                          const SizedBox(height: 24),
                          ActionQueueWidget(
                            needsAction: controller.needsAction.length,
                            important: controller.important.length,
                            archived: controller.archivedNotifications.length,
                            onQueueTap: (_) => onStartFocus(selectedFilter),
                          ),
                          const SizedBox(height: 24),
                          ScopeCard(
                            padding: const EdgeInsets.all(20),
                            child: ProgressWidget(
                              completed: controller.completedToday.length,
                              total: controller.notifications.length,
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Text('Focus Areas', style: theme.textTheme.titleMedium),
                            if (selectedFilter != null) ...[
                              const Spacer(),
                              TextButton(
                                onPressed: controller.clearFocusAreaFilter,
                                child: const Text('Clear filter'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
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
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _crossAxisCount(context),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.25,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final area = FocusArea.values[index];
                          final count = focusCounts[area]!;
                          final items = controller.notificationsForArea(area);
                          return FocusAreaCard(
                            area: area,
                            count: count,
                            description: area.descriptionFor(count, items),
                            selected: selectedFilter == area,
                            onTap: () {
                              controller.setFocusAreaFilter(
                                selectedFilter == area ? null : area,
                              );
                            },
                          );
                        },
                        childCount: FocusArea.values.length,
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
    return ScopeCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
          const SizedBox(width: 12),
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
