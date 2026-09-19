import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';

/// Explains why a notification matters using dynamic feature attribution influences.
class AIReasonWidget extends StatelessWidget {
  final AppNotification notification;
  final bool inverted;

  const AIReasonWidget({
    super.key,
    required this.notification,
    this.inverted = false,
  });

  List<String> get _reasons {
    final reasons = <String>[];
    final rawFeatures = notification.extractedFeatures;
    final features = rawFeatures != null ? ExtractedFeatures.fromMap(rawFeatures) : const ExtractedFeatures();

    final attributions = FeatureAttributionCalculator.computeAttributions(
      notification: notification,
      features: features,
      predictedScore: notification.priorityScore,
    );

    for (final attr in attributions) {
      reasons.add('${attr.featureName}: ${attr.description}');
    }

    if (notification.explanation != null && notification.explanation!.isNotEmpty) {
      final lines = notification.explanation!
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^[-•*]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .take(2);
      for (final line in lines) {
        if (!reasons.contains(line)) {
          reasons.add(line);
        }
      }
    }

    if (reasons.isEmpty) reasons.add('Thought you might want to see this.');
    return reasons.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = inverted
        ? theme.textTheme.titleSmall?.copyWith(color: Colors.white)
        : theme.textTheme.titleSmall;
    final bodyStyle = inverted
        ? theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72))
        : theme.textTheme.bodyMedium;
    final iconColor = inverted ? Colors.white38 : AppColors.muted(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Why this matters', style: titleStyle),
        const SizedBox(height: AppSpacing.sm),
        ..._reasons.map(
          (reason) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(reason, style: bodyStyle)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
