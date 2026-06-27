import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/motion/motion_surface.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';
import 'dart:math' as math;

/// New Daily Timeline showing an interactive timeline of notifications
class DailyTimelineScreen extends StatefulWidget {
  final NotificationController controller;

  const DailyTimelineScreen({
    super.key,
    required this.controller,
  });

  @override
  State<DailyTimelineScreen> createState() => _DailyTimelineScreenState();
}

class _DailyTimelineScreenState extends State<DailyTimelineScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Sort notifications by timestamp descending
    final notifications = List<AppNotification>.from(widget.controller.notifications)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Timeline'),
      ),
      body: ScopeScreenBody(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Hero(
                  tag: 'daily_brief_hero',
                  child: ScopeSurface(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Day So Far', style: theme.textTheme.titleLarge),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'You have ${notifications.length} notifications. '
                          '${widget.controller.reviewQueue.length} waiting for your attention.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final notification = notifications[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                      vertical: AppSpacing.sm,
                    ),
                    child: _TimelineItem(
                      notification: notification,
                      controller: widget.controller,
                    ),
                  );
                },
                childCount: notifications.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)), // Bottom padding
          ],
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final AppNotification notification;
  final NotificationController controller;

  const _TimelineItem({
    required this.notification,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.urgency(notification.priority);

    return MotionSurface(
      onTap: () {
        ScopeNavigator.push(
          context,
          NotificationDetailScreen(
            notification: notification,
            controller: controller,
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.priority == 'critical'
                ? AppColors.critical.withValues(alpha: 0.3)
                : AppColors.border,
            width: notification.priority == 'critical' ? 1.5 : 1.0,
          ),
          boxShadow: notification.priority == 'critical' ? [
            BoxShadow(
              color: AppColors.critical.withValues(alpha: 0.15),
              blurRadius: 16,
              spreadRadius: -4,
            )
          ] : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 4, right: AppSpacing.md),
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title.isNotEmpty ? notification.title : notification.packageName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: notification.priority == 'critical' ? FontWeight.bold : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(DateTime.fromMillisecondsSinceEpoch(notification.timestamp)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notification.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
