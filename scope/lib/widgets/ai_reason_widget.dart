import 'package:flutter/material.dart';
import 'package:scope/core/analysis/explainability_engine.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';

/// Interactive AI explainability widget displaying top feature attributions and score trace.
class AIReasonWidget extends StatelessWidget {
  final AppNotification notification;
  final bool inverted;

  const AIReasonWidget({
    super.key,
    required this.notification,
    this.inverted = false,
  });

  List<FeatureAttribution> get _attributions {
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final featureVector = FeatureExtractor.extractFromAppNotification(notification);

    return ExplainabilityEngine.computeFeatureAttributions(
      notification: notification,
      features: features,
      featureVector: featureVector,
      overrideTriggers: [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = inverted
        ? theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)
        : theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
    final bodyStyle = inverted
        ? theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))
        : theme.textTheme.bodyMedium;

    final attributions = _attributions;
    final score = notification.priorityScore ?? 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Why this matters', style: titleStyle),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (inverted ? Colors.white24 : AppColors.urgency(notification.priority)).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Fused Score: ${(score * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: inverted ? Colors.white : AppColors.urgency(notification.priority),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (attributions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('Thought you might want to see this.', style: bodyStyle),
          )
        else
          ...attributions.take(3).map((attr) {
            final isPos = attr.weight >= 0;
            final chipColor = isPos
                ? (inverted ? Colors.greenAccent : AppColors.success(context))
                : (inverted ? Colors.orangeAccent : AppColors.error(context));
            final weightStr = isPos ? '+${attr.weight.toStringAsFixed(2)}' : attr.weight.toStringAsFixed(2);

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    isPos ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: chipColor,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      attr.label,
                      style: bodyStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    weightStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: chipColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
