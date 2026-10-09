import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/models/notification_model.dart';

import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/ai_reason_widget.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';
import 'package:scope/widgets/smart_action_chip.dart';

/// Detail view — never auto-opens the originating app.
class NotificationDetailScreen extends StatelessWidget {
  final AppNotification notification;
  final NotificationController controller;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
    required this.controller,
  });

  String get _summary {
    if (notification.explanation != null && notification.explanation!.isNotEmpty) {
      return notification.explanation!.split('\n').first.replaceAll(RegExp(r'^[-•*]\s*'), '');
    }
    return notification.content.isNotEmpty
        ? notification.content
        : 'No additional summary available.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final actions = SmartActions.forNotification(notification);
    final urgencyColor = AppColors.urgency(notification.priority);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghost AI Analysis'),
        centerTitle: true,
      ),
      body: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: urgencyColor.withValues(alpha: 0.15),
                  child: Icon(Icons.apps, color: urgencyColor),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title.isNotEmpty ? notification.title : notification.packageName,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        notification.packageName,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (notification.priority != null && notification.priority != 'low')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: urgencyColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: urgencyColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      notification.priority!.toUpperCase(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: urgencyColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Why this matters', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.lg),
              borderColor: urgencyColor.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_summary, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  AIReasonWidget(notification: notification),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Suggested Actions', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions
                  .map(
                    (action) => SmartActionChip(
                      action: action,
                      onPressed: () => _handleAction(context, action),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text('Under the hood', style: theme.textTheme.titleMedium),
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                children: [
                  ScopeSurface(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailSection(title: 'Raw Message', child: Text(notification.content, style: theme.textTheme.bodyMedium)),
                        const SizedBox(height: AppSpacing.md),
                        _DetailSection(
                          title: 'What I found',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (features.hasDeadline)
                                const ScopeInfoRow(label: 'Deadline', value: 'Detected'),
                              if (features.amount != null)
                                const ScopeInfoRow(label: 'Amount', value: '₹[REDACTED_AMOUNT]'),
                              if (features.urls.isNotEmpty)
                                ScopeInfoRow(label: 'Website', value: features.urls.first),
                              if (features.phoneNumbers.isNotEmpty)
                                const ScopeInfoRow(label: 'Phone', value: '[REDACTED_PHONE]'),
                              if (features.emails.isNotEmpty)
                                const ScopeInfoRow(label: 'Email', value: '[REDACTED_EMAIL]'),
                              ScopeInfoRow(label: 'Organization', value: notification.packageName),
                              if (!features.hasDeadline &&
                                  features.amount == null &&
                                  features.urls.isEmpty &&
                                  features.phoneNumbers.isEmpty &&
                                  features.emails.isEmpty)
                                Text('No structured data extracted.', style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildFeatureAttributionSection(context, theme),
                        const SizedBox(height: AppSpacing.lg),
                        _buildScoreEvolutionSection(context, theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureAttributionSection(BuildContext context, ThemeData theme) {
    final rawAttributions = notification.extractedFeatures?['featureAttributions'] as List?;
    final attributions = rawAttributions != null
        ? rawAttributions
            .whereType<Map<String, dynamic>>()
            .map((r) => FeatureAttribution.fromMap(r))
            .toList()
        : <FeatureAttribution>[];

    if (attributions.isEmpty) {
      return const SizedBox.shrink();
    }

    return _DetailSection(
      title: 'Feature Attribution Breakdown',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: attributions.map((attr) {
          final isPositive = attr.direction == 'positive';
          final color = isPositive ? Colors.green : (attr.direction == 'negative' ? Colors.redAccent : Colors.grey);
          final icon = isPositive ? Icons.arrow_upward : (attr.direction == 'negative' ? Icons.arrow_downward : Icons.remove);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(attr.displayName, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      if (attr.description.isNotEmpty)
                        Text(attr.description, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  '${isPositive ? "+" : ""}${(attr.weight * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScoreEvolutionSection(BuildContext context, ThemeData theme) {
    final rawEvolution = notification.extractedFeatures?['scoreEvolution'] as List?;
    final steps = rawEvolution != null
        ? rawEvolution
            .whereType<Map<String, dynamic>>()
            .map((r) => ScoreEvolutionStep.fromMap(r))
            .toList()
        : <ScoreEvolutionStep>[];

    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }

    return _DetailSection(
      title: 'Score Evolution Trace',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.map((step) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(step.stage, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      '${(step.scoreBefore * 100).toStringAsFixed(0)}% → ${(step.scoreAfter * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(step.action, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
                if (step.details.isNotEmpty)
                  Text(step.details, style: theme.textTheme.bodySmall),
                const Divider(height: 12),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }


  void _handleAction(BuildContext context, SmartAction action) {
    bool shouldPop = false;
    switch (action.type) {
      case SmartActionType.archive:
        controller.archive(notification.id);
        shouldPop = true;
        break;
      case SmartActionType.complete:
        controller.complete(notification.id);
        shouldPop = true;
        break;
      case SmartActionType.addCalendar:
        controller.saveActionItem(notification, action);
        controller.recordCalendarEvent();
        shouldPop = true;
        break;
      case SmartActionType.remind:
        controller.saveActionItem(notification, action);
        controller.recordReminder();
        shouldPop = true;
        break;
      case SmartActionType.track:
        controller.saveActionItem(notification, action);
        controller.recordAction();
        shouldPop = true;
        break;
      default:
        controller.recordAction();
        controller.complete(notification.id); // Mark complete since we are executing it
        shouldPop = true;
        break;
    }
    
    if (context.mounted) {
      final isGeneric = action.type == SmartActionType.archive || 
                        action.type == SmartActionType.complete ||
                        action.type == SmartActionType.addCalendar ||
                        action.type == SmartActionType.remind ||
                        action.type == SmartActionType.track;
      
      final msg = isGeneric 
          ? '${action.label} recorded'
          : 'Opening App for: ${action.label}...';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
      
      if (shouldPop && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: title),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}
