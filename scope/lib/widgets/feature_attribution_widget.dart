import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Renders a breakdown of model feature weight influences.
class FeatureAttributionWidget extends StatelessWidget {
  final AppNotification notification;
  final List<FeatureAttribution>? attributions;

  const FeatureAttributionWidget({
    super.key,
    required this.notification,
    this.attributions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();

    final computedAttributions = attributions ??
        FeatureAttributionCalculator.computeAttributions(
          notification: notification,
          features: features,
          predictedScore: notification.priorityScore,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Feature Weight Influences',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...computedAttributions.map(
          (attr) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  _ImpactBadge(impact: attr.impact, influence: attr.influence),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attr.featureName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          attr.description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImpactBadge extends StatelessWidget {
  final String impact;
  final double influence;

  const _ImpactBadge({
    required this.impact,
    required this.influence,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String sign;

    if (impact == 'positive' || influence > 0) {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade700;
      sign = '+';
    } else if (impact == 'negative' || influence < 0) {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red.shade700;
      sign = '';
    } else {
      bg = Colors.grey.withValues(alpha: 0.15);
      fg = Colors.grey.shade700;
      sign = '';
    }

    final percentage = (influence * 100).abs().toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$sign$percentage%',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
