import 'package:flutter/material.dart';
import 'package:scope/core/analysis/explainability_engine.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_chip.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Interactive visualizer widget displaying feature attributions, policy overrides,
/// and score evolution traces for prioritized notifications.
class ModelExplainabilityWidget extends StatelessWidget {
  final AppNotification notification;
  final InferenceAuditLogEntry? auditLog;
  final bool compact;

  const ModelExplainabilityWidget({
    super.key,
    required this.notification,
    this.auditLog,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgencyColor = AppColors.urgency(notification.priority);

    // Extract attributions from auditLog if available, or compute on the fly
    final attributions = _getAttributions();
    final scoreSteps = _getScoreEvolutionSteps();
    final overrideTriggers = _getOverrideTriggers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Row(
          children: [
            Icon(Icons.auto_graph, color: urgencyColor, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Model Explainability & Feature Attribution',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // 1. Policy Engine Overrides Banner (if any)
        if (overrideTriggers.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.warning(context).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.gavel,
                      size: 16,
                      color: AppColors.warning(context),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Policy Engine Overrides Applied',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.warning(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: overrideTriggers
                      .map(
                        (trigger) => ScopeChip(
                          label: _formatTriggerLabel(trigger),
                          accent: AppColors.warning(context),
                          tone: ScopeChipTone.accent,
                          icon: Icons.shield,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 2. Feature Attribution Breakdown Card
        ScopeSurface(
          padding: const EdgeInsets.all(AppSpacing.md),
          borderColor: urgencyColor.withValues(alpha: 0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top Feature Attribution Weights',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Influence of extracted signals on priority score:',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              if (attributions.isEmpty)
                Text(
                  'No strong feature attributions detected.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                ...attributions.take(compact ? 3 : 6).map(
                      (attr) => _buildAttributionBar(context, attr),
                    ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 3. Score Evolution Timeline
        ScopeSurface(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Score Evolution Trace',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Step-by-step score progression across pipeline stages:',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              ...scoreSteps.asMap().entries.map((entry) {
                final isLast = entry.key == scoreSteps.length - 1;
                return _buildScoreStepRow(context, entry.value, isLast);
              }),
            ],
          ),
        ),
      ],
    );
  }

  List<FeatureAttribution> _getAttributions() {
    if (auditLog != null && auditLog!.topFeatureAttributions != null) {
      final map = auditLog!.topFeatureAttributions!;
      final list = <FeatureAttribution>[];
      map.forEach((label, weight) {
        list.add(FeatureAttribution(
          featureName: label,
          label: label,
          weight: (weight as num).toDouble(),
        ));
      });
      if (list.isNotEmpty) return list;
    }

    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final featureVector = FeatureExtractor.extractFromAppNotification(notification);
    final overrideTriggers = _getOverrideTriggers();

    return ExplainabilityEngine.computeFeatureAttributions(
      notification: notification,
      features: features,
      featureVector: featureVector,
      overrideTriggers: overrideTriggers,
    );
  }

  List<ScoreEvolutionStep> _getScoreEvolutionSteps() {
    final rawScore = auditLog?.rawModelScore ?? notification.priorityScore ?? 0.5;
    final ruleScore = auditLog?.ruleMatchScore;
    final fusedScore = auditLog?.fusedScore ?? rawScore;
    final finalScore = auditLog?.finalScore ?? notification.priorityScore ?? 0.5;
    final overrideTriggers = _getOverrideTriggers();
    final priority = notification.priority ?? 'medium';

    return ExplainabilityEngine.buildScoreEvolutionTrace(
      rawModelScore: rawScore,
      ruleMatchScore: ruleScore,
      fusedScore: fusedScore,
      finalScore: finalScore,
      overrideTriggers: overrideTriggers,
      priority: priority,
    );
  }

  List<String> _getOverrideTriggers() {
    if (auditLog?.overrideTriggers != null && auditLog!.overrideTriggers!.isNotEmpty) {
      return auditLog!.overrideTriggers!.split(',').where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  String _formatTriggerLabel(String trigger) {
    if (trigger.contains('social')) return 'Social Package Ceiling (-0.20)';
    if (trigger.contains('media')) return 'Media Package Ceiling (-0.25)';
    if (trigger.contains('promo')) return 'Shopping / Promo Ceiling (-0.30)';
    if (trigger.contains('expired_otp')) return 'Expired Security OTP (Demoted to 0)';
    if (trigger.contains('expired_reminder')) return 'Expired Deadline (Demoted to 0)';
    if (trigger.contains('duplicate')) return 'Duplicate Evicted (Demoted to 0)';
    if (trigger.contains('completed')) return 'Completed Task (Demoted to 0)';
    if (trigger.contains('status')) return 'Status Notification Ignored';
    return trigger.replaceAll('_', ' ').toUpperCase();
  }

  Widget _buildAttributionBar(BuildContext context, FeatureAttribution attr) {
    final theme = Theme.of(context);
    final isPositive = attr.weight >= 0;
    final barColor = isPositive ? AppColors.success(context) : AppColors.error(context);
    final weightFormatted = isPositive
        ? '+${attr.weight.toStringAsFixed(2)}'
        : attr.weight.toStringAsFixed(2);
    final normalizedWidth = (attr.weight.abs() / 0.5).clamp(0.05, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  attr.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                weightFormatted,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: barColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: normalizedWidth,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreStepRow(BuildContext context, ScoreEvolutionStep step, bool isLast) {
    final theme = Theme.of(context);
    final stepColor = AppColors.urgencyFromScore(step.score);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: stepColor.withValues(alpha: 0.2),
                child: Text(
                  (step.score * 10).toStringAsFixed(0),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: stepColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 20,
                  color: theme.dividerColor,
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      step.stageName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(step.score * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: stepColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  step.description,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
