import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/widgets/scope_card.dart';

/// Compact insight card for search results and lists.
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
    final priority = notification.priority ?? 'medium';
    final accent = AppTheme.urgencyColor(priority);

    return ScopeCard(
      onTap: onTap,
      borderColor: accent.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  notification.title.isNotEmpty ? notification.title : '(No title)',
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (notification.priority != null)
                Text(
                  notification.priority!.toUpperCase(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
            ],
          ),
          if (notification.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notification.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
