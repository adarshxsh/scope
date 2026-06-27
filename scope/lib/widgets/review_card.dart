import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/ai_reason_widget.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/section_header.dart';
import 'package:scope/widgets/smart_action_chip.dart';

/// Guided single-notification review card.
class ReviewCard extends StatelessWidget {
  final AppNotification notification;
  final List<SmartAction> actions;
  final void Function(SmartAction action)? onAction;
  final SmartActionType? selectedAction;
  final int currentIndex;
  final int totalCount;
  final bool inverted;

  const ReviewCard({
    super.key,
    required this.notification,
    required this.actions,
    this.onAction,
    this.selectedAction,
    required this.currentIndex,
    required this.totalCount,
    this.inverted = false,
  });

  String get _application {
    final pkg = notification.packageName;
    if (pkg.contains('.')) {
      return pkg.split('.').last.replaceAll('_', ' ').toUpperCase();
    }
    return pkg;
  }

  String get _summary {
    final features = notification.extractedFeatures;
    if (features?['hasDeadline'] == true) return 'Application closes soon.';
    if (notification.content.isNotEmpty) {
      final content = notification.content;
      return content.length > 120 ? '${content.substring(0, 117)}...' : content;
    }
    return 'Review and choose your next action.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCritical = notification.priority == 'critical';
    final isLow = notification.priority == 'low';
    final accent = AppColors.urgency(notification.priority);
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final quickActions = actions.where((a) => a.type != SmartActionType.archive).toList();

    final titleStyle = inverted
        ? theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: isCritical ? FontWeight.bold : null,
            fontSize: isCritical ? 26 : (isLow ? 20 : 24),
          )
        : theme.textTheme.headlineSmall?.copyWith(
            fontWeight: isCritical ? FontWeight.bold : null,
            fontSize: isCritical ? 26 : (isLow ? 20 : 24),
          );
          
    final bodyStyle = inverted
        ? theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: isLow ? 0.6 : 0.78),
            fontSize: isLow ? 14 : 16,
          )
        : theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: isLow ? 0.6 : 0.78),
            fontSize: isLow ? 14 : 16,
          );
          
    final metaStyle = inverted
        ? theme.textTheme.bodySmall?.copyWith(color: Colors.white38)
        : theme.textTheme.labelLarge;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (onAction != null)
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: inverted ? Colors.white54 : null),
                onPressed: () => onAction!(const SmartAction(
                  label: 'Archive',
                  icon: Icons.archive,
                  type: SmartActionType.archive,
                )),
                tooltip: 'Archive',
                visualDensity: VisualDensity.compact,
              ),
            Expanded(child: Text(_application, style: metaStyle)),
            Text('${currentIndex + 1} / $totalCount', style: metaStyle),
          ],
        ),
        SizedBox(height: isLow ? AppSpacing.sm : AppSpacing.md),
        if (notification.priority != null && notification.priority != 'low')
          Padding(
            padding: EdgeInsets.only(bottom: isLow ? AppSpacing.sm : AppSpacing.md),
            child: Text(
              notification.priority?.toUpperCase() ?? '',
              style: metaStyle?.copyWith(color: accent, letterSpacing: 0.8, fontWeight: isCritical ? FontWeight.bold : null),
            ),
          ),
        Text(
          notification.title.isNotEmpty ? notification.title : 'Notification',
          style: titleStyle,
        ),
        SizedBox(height: isLow ? AppSpacing.sm : AppSpacing.md),
        Text(
          _summary,
          style: bodyStyle,
          maxLines: isLow ? 2 : 5,
          overflow: TextOverflow.ellipsis,
        ),
        if (!isLow) ...[
          const SizedBox(height: AppSpacing.lg),
          Divider(color: inverted ? Colors.white12 : null, height: 1),
          const SizedBox(height: AppSpacing.md),
          AIReasonWidget(notification: notification, inverted: inverted),
        ],
        if (_hasDetectedInfo(features)) ...[
          const SizedBox(height: AppSpacing.md),
          DetectedInfoPanel(features: features, inverted: inverted),
        ],
        const SizedBox(height: AppSpacing.lg),
        Divider(color: inverted ? Colors.white12 : null, height: 1),
        const SizedBox(height: AppSpacing.md),
        SectionLabel(label: 'Quick Actions', color: inverted ? Colors.white38 : null),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: quickActions
              .map(
                (action) => SmartActionChip(
                  action: action,
                  inverted: inverted,
                  selected: selectedAction == action.type,
                  onPressed: onAction == null ? null : () => onAction!(action),
                ),
              )
              .toList(),
        ),
      ],
    );

    if (inverted) return content;

    return ScopeSurface(
      borderColor: accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: content,
    );
  }

  bool _hasDetectedInfo(ExtractedFeatures features) {
    return features.hasDeadline ||
        features.amount != null ||
        features.urls.isNotEmpty ||
        features.phoneNumbers.isNotEmpty;
  }
}

/// Shared detected-info panel.
class DetectedInfoPanel extends StatelessWidget {
  final ExtractedFeatures features;
  final bool inverted;

  const DetectedInfoPanel({super.key, required this.features, this.inverted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = inverted
        ? theme.textTheme.titleSmall?.copyWith(color: Colors.white)
        : theme.textTheme.titleSmall;
    final rowColor = inverted ? Colors.white60 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detected', style: titleStyle),
        const SizedBox(height: AppSpacing.sm),
        if (features.hasDeadline)
          _DetectedLine(icon: Icons.event, text: 'Deadline detected', color: rowColor),
        if (features.amount != null)
          _DetectedLine(icon: Icons.currency_rupee, text: '₹${features.amount}', color: rowColor),
        if (features.urls.isNotEmpty)
          _DetectedLine(icon: Icons.link, text: features.urls.first, color: rowColor),
        if (features.phoneNumbers.isNotEmpty)
          _DetectedLine(icon: Icons.phone, text: features.phoneNumbers.first, color: rowColor),
      ],
    );
  }
}

class _DetectedLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _DetectedLine({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm - 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppColors.muted(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color))),
        ],
      ),
    );
  }
}
