import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Compact insight card for search results.
class NotificationInsightCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;

  const NotificationInsightCard({
    super.key,
    required this.notification,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priority = notification.priority ?? 'medium';
    final showUrgency = priority == 'critical' || priority == 'high';

    return ScopeSurface(
      onTap: onTap,
      borderColor: showUrgency ? AppColors.urgency(priority).withValues(alpha: 0.12) : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notification.title.isNotEmpty ? notification.title : '(No title)',
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (notification.content.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              notification.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (showUrgency) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              priority.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.urgency(priority),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
