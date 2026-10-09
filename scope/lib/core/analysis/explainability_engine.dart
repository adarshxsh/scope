import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';

/// Represents a single feature attribution entry with its directional weight.
class FeatureAttribution {
  final String featureName;
  final String label;
  final double weight; // Positive for priority boost, negative for demotion

  const FeatureAttribution({
    required this.featureName,
    required this.label,
    required this.weight,
  });

  Map<String, dynamic> toMap() => {
        'featureName': featureName,
        'label': label,
        'weight': weight,
      };

  factory FeatureAttribution.fromMap(Map<String, dynamic> map) {
    return FeatureAttribution(
      featureName: (map['featureName'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Represents a single stage transition step in the score evolution trace.
class ScoreEvolutionStep {
  final String stageName; // e.g., 'Raw Model', 'Rule Fusion', 'Policy Override', 'Final Score'
  final double score;
  final String description;

  const ScoreEvolutionStep({
    required this.stageName,
    required this.score,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
        'stageName': stageName,
        'score': score,
        'description': description,
      };

  factory ScoreEvolutionStep.fromMap(Map<String, dynamic> map) {
    return ScoreEvolutionStep(
      stageName: (map['stageName'] ?? '').toString(),
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      description: (map['description'] ?? '').toString(),
    );
  }
}

/// On-device explainability engine computing quantitative feature attributions
/// and score evolution traces for prioritized notifications.
class ExplainabilityEngine {
  /// Extracts top feature attributions (positive and negative weights) for a notification.
  static List<FeatureAttribution> computeFeatureAttributions({
    required AppNotification notification,
    required ExtractedFeatures features,
    required List<double> featureVector,
    required List<String> overrideTriggers,
  }) {
    final attributions = <FeatureAttribution>[];

    // Helper to get vector value safely
    double getVal(int idx) => (idx >= 0 && idx < featureVector.length) ? featureVector[idx] : 0.0;

    // 1. Positive feature attributions
    if (getVal(11) == 1.0 || features.otp != null) {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_otp',
        label: 'OTP / Security Code',
        weight: 0.45,
      ));
    }

    if (getVal(28) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_security_keywords',
        label: 'Security Alert Trigger',
        weight: 0.35,
      ));
    }

    if (features.amount != null || getVal(10) == 1.0 || getVal(50) > 0) {
      final amtLabel = features.amount != null ? 'Payment Amount (₹${features.amount})' : 'Monetary Transaction';
      attributions.add(FeatureAttribution(
        featureName: 'contains_money',
        label: amtLabel,
        weight: 0.35,
      ));
    }

    if (features.hasDeadline || getVal(27) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_deadline',
        label: 'Time-sensitive Deadline',
        weight: 0.30,
      ));
    }

    if (getVal(29) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_payment_keywords',
        label: 'Financial Invoice Signal',
        weight: 0.25,
      ));
    }

    if (getVal(31) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_work_keywords',
        label: 'Work / Meeting Calendar Signal',
        weight: 0.20,
      ));
    }

    if (getVal(30) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_delivery_keywords',
        label: 'Shipment / Delivery Update',
        weight: 0.20,
      ));
    }

    if (getVal(35) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'conversation',
        label: 'Direct Conversation / DM',
        weight: 0.15,
      ));
    }

    if (getVal(44) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'requires_action',
        label: 'Action Required',
        weight: 0.10,
      ));
    }

    // 2. Negative feature attributions / demotions
    if (getVal(20) == 1.0 || getVal(46) == 1.0 || notification.classifiedCategory == 'promo') {
      attributions.add(const FeatureAttribution(
        featureName: 'is_promotion',
        label: 'Promotional Offer / Discount',
        weight: -0.35,
      ));
    }

    if (getVal(32) == 1.0 || notification.classifiedCategory == 'social') {
      attributions.add(const FeatureAttribution(
        featureName: 'contains_social_keywords',
        label: 'Social Engagement Signal',
        weight: -0.25,
      ));
    }

    if (getVal(37) == 1.0) {
      attributions.add(const FeatureAttribution(
        featureName: 'ongoing',
        label: 'Ongoing System Service',
        weight: -0.20,
      ));
    }

    // Overrides as explicit attributions
    for (final trigger in overrideTriggers) {
      if (trigger.contains('social_package_ceiling') || trigger.contains('package_ceiling:social')) {
        attributions.add(const FeatureAttribution(
          featureName: 'package_ceiling_social',
          label: 'Package Ceiling (Social Media)',
          weight: -0.20,
        ));
      } else if (trigger.contains('media_package_ceiling') || trigger.contains('package_ceiling:media')) {
        attributions.add(const FeatureAttribution(
          featureName: 'package_ceiling_media',
          label: 'Package Ceiling (Media Player)',
          weight: -0.25,
        ));
      } else if (trigger.contains('promo_package_ceiling') || trigger.contains('package_ceiling:promo')) {
        attributions.add(const FeatureAttribution(
          featureName: 'package_ceiling_promo',
          label: 'Package Ceiling (Shopping)',
          weight: -0.30,
        ));
      } else if (trigger.contains('expired_otp')) {
        attributions.add(const FeatureAttribution(
          featureName: 'expired_otp_override',
          label: 'Expired Security Code',
          weight: -0.80,
        ));
      } else if (trigger.contains('expired_reminder')) {
        attributions.add(const FeatureAttribution(
          featureName: 'expired_reminder_override',
          label: 'Expired Deadline',
          weight: -0.80,
        ));
      } else if (trigger.contains('duplicate')) {
        attributions.add(const FeatureAttribution(
          featureName: 'duplicate_override',
          label: 'Duplicate Notification Evicted',
          weight: -0.60,
        ));
      } else if (trigger.contains('completed_task')) {
        attributions.add(const FeatureAttribution(
          featureName: 'completed_task_override',
          label: 'Completed Action Item',
          weight: -0.50,
        ));
      }
    }

    // Sort by absolute weight descending
    attributions.sort((a, b) => b.weight.abs().compareTo(a.weight.abs()));

    return attributions;
  }

  /// Generates step-by-step score evolution steps for visualization.
  static List<ScoreEvolutionStep> buildScoreEvolutionTrace({
    required double rawModelScore,
    required double? ruleMatchScore,
    required double fusedScore,
    required double finalScore,
    required List<String> overrideTriggers,
    required String priority,
  }) {
    final steps = <ScoreEvolutionStep>[];

    // Stage 1: Raw Model Prediction
    steps.add(ScoreEvolutionStep(
      stageName: 'Raw Model',
      score: rawModelScore,
      description: 'Neural MLP model regression output (${(rawModelScore * 100).toStringAsFixed(0)}%)',
    ));

    // Stage 2: Rule Fusion
    if (ruleMatchScore != null) {
      steps.add(ScoreEvolutionStep(
        stageName: 'Rule Fusion',
        score: fusedScore,
        description: 'Blended with Rule Engine match (${(ruleMatchScore * 100).toStringAsFixed(0)}%)',
      ));
    } else {
      steps.add(ScoreEvolutionStep(
        stageName: 'Rule Fusion',
        score: fusedScore,
        description: 'No deterministic rule match',
      ));
    }

    // Stage 3: Policy Override
    if (overrideTriggers.isNotEmpty) {
      final overrideDesc = overrideTriggers.join(', ');
      steps.add(ScoreEvolutionStep(
        stageName: 'Policy Override',
        score: finalScore,
        description: 'Gated by Policy Engine: $overrideDesc',
      ));
    } else {
      steps.add(ScoreEvolutionStep(
        stageName: 'Policy Override',
        score: finalScore,
        description: 'Passed deterministic policy gates',
      ));
    }

    // Stage 4: Final Score
    steps.add(ScoreEvolutionStep(
      stageName: 'Final Score',
      score: finalScore,
      description: 'Assigned Priority: ${priority.toUpperCase()} (${(finalScore * 100).toStringAsFixed(0)}%)',
    ));

    return steps;
  }
}
