import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/widgets/ai_reason_widget.dart';
import 'package:scope/widgets/scope_card.dart';
import 'package:scope/widgets/smart_action_chip.dart';

/// Guided single-notification review card — no scrolling, action-first layout.
class ReviewCard extends StatelessWidget {
  final AppNotification notification;
  final List<SmartAction> actions;
  final void Function(SmartAction action)? onAction;
  final SmartActionType? selectedAction;
  final int currentIndex;
  final int totalCount;

  const ReviewCard({
    super.key,
    required this.notification,
    required this.actions,
    this.onAction,
    this.selectedAction,
    required this.currentIndex,
    required this.totalCount,
  });

  String get _application {
    final pkg = notification.packageName;
    if (pkg.contains('.')) {
      final parts = pkg.split('.');
      return parts.last.replaceAll('_', ' ').toUpperCase();
    }
    return pkg;
  }

  String get _summary {
    final features = notification.extractedFeatures;
    if (features?['hasDeadline'] == true) {
      return 'Application closes soon.';
    }
    if (notification.content.isNotEmpty) {
      final content = notification.content;
      return content.length > 120 ? '${content.substring(0, 117)}...' : content;
    }
    return 'Review and choose your next action.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.urgencyColor(notification.priority);
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final quickActions = actions.where((a) => a.type != SmartActionType.archive).toList();

    return ScopeCard(
      borderColor: accent.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  if (onAction != null) {
                    onAction!(const SmartAction(
                      label: 'Archive',
                      icon: Icons.archive,
                      type: SmartActionType.archive,
                    ));
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                tooltip: 'Archive notification',
              ),
              const SizedBox(width: 8),
              Text(_application, style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 0.8)),
              const Spacer(),
              Text('${currentIndex + 1} / $totalCount', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title.isNotEmpty ? notification.title : notification.packageName,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(_summary, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  AIReasonWidget(notification: notification),
                  if (_hasDetectedInfo(features)) ...[
                    const SizedBox(height: 16),
                    _DetectedInfo(features: features),
                  ],
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text('Quick Actions', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickActions
                        .map(
                          (action) => SmartActionChip(
                            action: action,
                            selected: selectedAction == action.type,
                            onPressed: onAction == null ? null : () => onAction!(action),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasDetectedInfo(ExtractedFeatures features) {
    return features.hasDeadline ||
        features.amount != null ||
        features.urls.isNotEmpty ||
        features.phoneNumbers.isNotEmpty;
  }
}

class _DetectedInfo extends StatelessWidget {
  final ExtractedFeatures features;

  const _DetectedInfo({required this.features});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detected', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (features.hasDeadline) _row(context, Icons.event, 'Deadline detected'),
        if (features.amount != null) _row(context, Icons.currency_rupee, '₹${features.amount}'),
        if (features.urls.isNotEmpty) _row(context, Icons.link, features.urls.first),
        if (features.phoneNumbers.isNotEmpty) _row(context, Icons.phone, features.phoneNumbers.first),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
