import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/scope_navigator.dart';

class SavedActionItemsWidget extends StatelessWidget {
  final NotificationController controller;

  const SavedActionItemsWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final items = controller.savedActionItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            'Saved for Later',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 60,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final item = items[index];
              return InkWell(
                onTap: () {
                  ScopeNavigator.push(
                    context,
                    NotificationDetailScreen(
                      notification: item.notification,
                      controller: controller,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: item.action.color?.withValues(alpha: 0.15) ?? Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: item.action.color?.withValues(alpha: 0.3) ?? Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.action.icon, size: 16, color: item.action.color ?? Colors.white70),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.action.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: item.action.color ?? Colors.white,
                            ),
                          ),
                          Text(
                            item.notification.title.isEmpty ? item.notification.packageName : item.notification.title,
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
