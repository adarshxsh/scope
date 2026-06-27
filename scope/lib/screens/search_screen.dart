import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/motion/motion_surface.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Search across captured notifications.
class SearchScreen extends StatefulWidget {
  final NotificationController controller;

  const SearchScreen({super.key, required this.controller});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  String _query = '';

  final Set<String> _dismissedIds = {};

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ScopeScreenBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Search',
              subtitle: 'Find anything by title, content, or app.',
            ),
            SearchBar(
              controller: _queryController,
              hintText: 'Search notifications…',
              leading: const Icon(Icons.search_rounded),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final results = widget.controller
                      .search(_query)
                      .where((n) => !_dismissedIds.contains(n.id))
                      .toList();

                  if (results.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_outlined,
                      title: _query.trim().isEmpty ? 'No notifications' : 'No matches',
                      message: _query.trim().isEmpty
                          ? 'Wait for notifications to arrive.'
                          : 'Nothing found for "$_query".',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl, left: AppSpacing.md, right: AppSpacing.md),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final notification = results[index];
                      return _SwipeableSearchTile(
                        notification: notification,
                        controller: widget.controller,
                        onDismissed: (direction) {
                          setState(() {
                            _dismissedIds.add(notification.id);
                          });
                          if (direction == DismissDirection.startToEnd) {
                            widget.controller.archive(notification.id);
                          } else {
                            widget.controller.complete(notification.id);
                          }
                        },
                      );
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

class _SwipeableSearchTile extends StatelessWidget {
  final AppNotification notification;
  final NotificationController controller;
  final Function(DismissDirection) onDismissed;

  const _SwipeableSearchTile({
    required this.notification,
    required this.controller,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLow = notification.priority == 'low';

    return Dismissible(
      key: ValueKey(notification.id),
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: const Icon(Icons.archive_outlined, color: Colors.white),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade800,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: const Icon(Icons.check_circle_outline, color: Colors.white),
      ),
      onDismissed: onDismissed,
      child: MotionSurface(
        onTap: () => ScopeNavigator.push(
          context,
          NotificationDetailScreen(
            notification: notification,
            controller: controller,
          ),
        ),
        child: Opacity(
          opacity: isLow ? 0.4 : 1.0,
          child: Container(
            margin: EdgeInsets.symmetric(vertical: isLow ? 2 : 4),
            padding: EdgeInsets.all(isLow ? AppSpacing.sm : AppSpacing.md),
            decoration: BoxDecoration(
              color: notification.priority == 'high' 
                  ? AppColors.high.withValues(alpha: 0.05)
                  : const Color(0xFF161A23),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: notification.priority == 'critical'
                    ? AppColors.critical.withValues(alpha: 0.3)
                    : const Color(0xFF262A36),
                width: notification.priority == 'critical' ? 1.5 : 1.0,
              ),
              boxShadow: notification.priority == 'critical' ? [
                BoxShadow(
                  color: AppColors.critical.withValues(alpha: 0.15),
                  blurRadius: 24,
                  spreadRadius: -4,
                )
              ] : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getPriorityColor(notification.priority).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getPriorityIcon(notification.priority),
                    color: _getPriorityColor(notification.priority),
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title.isNotEmpty ? notification.title : '(No title)',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: (notification.priority == 'critical' || notification.priority == 'high')
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(notification.timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                          ),
                        ],
                      ),
                      if (notification.content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          notification.content,
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        notification.packageName,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(String? priority) {
    switch (priority) {
      case 'critical': return const Color(0xFFE05252);
      case 'high': return const Color(0xFFE5923A);
      case 'medium': return const Color(0xFF3A7BD5);
      case 'low': return const Color(0xFF6B7A99);
      default: return Colors.grey;
    }
  }

  IconData _getPriorityIcon(String? priority) {
    switch (priority) {
      case 'critical': return Icons.gpp_bad;
      case 'high': return Icons.warning_amber_rounded;
      case 'medium': return Icons.notifications;
      case 'low': return Icons.notifications_none;
      default: return Icons.notifications;
    }
  }

  String _formatTime(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
