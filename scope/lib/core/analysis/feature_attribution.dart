import 'dart:convert';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/utils/pii_redactor.dart';

/// Represents the weight and directional influence of a single feature on model inference.
class FeatureAttribution {
  final String featureKey;
  final String displayName;
  final double weight;
  final String direction; // 'positive', 'negative', 'neutral'
  final String description;

  const FeatureAttribution({
    required this.featureKey,
    required this.displayName,
    required this.weight,
    required this.direction,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'featureKey': featureKey,
      'displayName': displayName,
      'weight': weight,
      'direction': direction,
      'description': description,
    };
  }

  factory FeatureAttribution.fromMap(Map<String, dynamic> map) {
    return FeatureAttribution(
      featureKey: map['featureKey'] as String? ?? 'unknown',
      displayName: map['displayName'] as String? ?? 'Unknown Feature',
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
      direction: map['direction'] as String? ?? 'neutral',
      description: map['description'] as String? ?? '',
    );
  }

  /// Computes feature attributions from a 63-element feature vector and extracted features.
  static List<FeatureAttribution> computeFromVector({
    required List<double> featureVector,
    required ExtractedFeatures features,
    required String category,
  }) {
    final attributions = <FeatureAttribution>[];

    // Helper to add attribution if active
    void check(int idx, String key, String name, double weight, String posDesc, String negDesc) {
      if (idx < featureVector.length) {
        final val = featureVector[idx];
        if (val.isFinite && val > 0.0) {
          attributions.add(FeatureAttribution(
            featureKey: key,
            displayName: name,
            weight: weight,
            direction: weight >= 0 ? 'positive' : 'negative',
            description: weight >= 0 ? posDesc : negDesc,
          ));
        }
      }
    }

    // OTP detection (index 11)
    if (features.otp != null || (featureVector.length > 11 && featureVector[11] == 1.0)) {
      attributions.add(const FeatureAttribution(
        featureKey: 'contains_otp',
        displayName: 'Verification / OTP Code',
        weight: 0.45,
        direction: 'positive',
        description: 'Contains a sensitive authentication passcode [REDACTED_OTP].',
      ));
    }

    // Monetary Amount (index 10 / 50)
    if (features.amount != null || (featureVector.length > 10 && featureVector[10] == 1.0)) {
      attributions.add(const FeatureAttribution(
        featureKey: 'contains_money',
        displayName: 'Monetary Transaction',
        weight: 0.35,
        direction: 'positive',
        description: 'Includes financial payment details or balance update.',
      ));
    }

    // Currency Symbol (index 9)
    check(
      9,
      'contains_currency_symbol',
      'Currency Indicator',
      0.15,
      'Contains monetary symbol or currency token.',
      '',
    );

    // Urgent Deadline (index 27)
    if (features.hasDeadline || (featureVector.length > 27 && featureVector[27] == 1.0)) {
      attributions.add(const FeatureAttribution(
        featureKey: 'contains_deadline',
        displayName: 'Time-Sensitive Deadline',
        weight: 0.25,
        direction: 'positive',
        description: 'Includes urgent timing or relative deadline indicators.',
      ));
    }

    // Transaction ID (index 22)
    check(
      22,
      'contains_transaction_id',
      'Transaction Identifier',
      0.20,
      'Contains order or transaction reference code.',
      '',
    );

    // Payment Keywords (index 29)
    check(
      29,
      'contains_payment_keywords',
      'Payment Keywords',
      0.25,
      'Contains explicit billing or payment action terms.',
      '',
    );

    // Promotional Category / Keywords (index 20)
    if (category == 'promo' || (featureVector.length > 20 && featureVector[20] == 1.0)) {
      attributions.add(const FeatureAttribution(
        featureKey: 'contains_promo_keywords',
        displayName: 'Promotional Content',
        weight: -0.30,
        direction: 'negative',
        description: 'Contains marketing discount or promotional terms.',
      ));
    }

    // Actionable Links / Contacts
    if (features.urls.isNotEmpty) {
      attributions.add(FeatureAttribution(
        featureKey: 'urls',
        displayName: 'Actionable Link',
        weight: 0.10,
        direction: 'positive',
        description: 'Includes ${features.urls.length} embedded web link(s).',
      ));
    }

    if (features.phoneNumbers.isNotEmpty || features.emails.isNotEmpty) {
      attributions.add(const FeatureAttribution(
        featureKey: 'contact_info',
        displayName: 'Contact Information',
        weight: 0.10,
        direction: 'positive',
        description: 'Includes direct contact information.',
      ));
    }

    // Category Specific Attributions
    if (category == 'finance') {
      attributions.add(const FeatureAttribution(
        featureKey: 'category_finance',
        displayName: 'Financial Domain',
        weight: 0.30,
        direction: 'positive',
        description: 'Classified under critical financial services category.',
      ));
    } else if (category == 'social') {
      attributions.add(const FeatureAttribution(
        featureKey: 'category_social',
        displayName: 'Social Domain',
        weight: -0.20,
        direction: 'negative',
        description: 'Classified under social media network category.',
      ));
    }

    if (attributions.isEmpty) {
      attributions.add(const FeatureAttribution(
        featureKey: 'general_text',
        displayName: 'Standard Notification Text',
        weight: 0.05,
        direction: 'neutral',
        description: 'Evaluated using default natural language semantic features.',
      ));
    }

    return attributions;
  }
}

/// Represents a single step in priority score resolution.
class ScoreEvolutionStep {
  final String stage;
  final double scoreBefore;
  final double scoreAfter;
  final String action;
  final String details;

  const ScoreEvolutionStep({
    required this.stage,
    required this.scoreBefore,
    required this.scoreAfter,
    required this.action,
    required this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'stage': stage,
      'scoreBefore': scoreBefore,
      'scoreAfter': scoreAfter,
      'action': action,
      'details': details,
    };
  }

  factory ScoreEvolutionStep.fromMap(Map<String, dynamic> map) {
    return ScoreEvolutionStep(
      stage: map['stage'] as String? ?? '',
      scoreBefore: (map['scoreBefore'] as num?)?.toDouble() ?? 0.0,
      scoreAfter: (map['scoreAfter'] as num?)?.toDouble() ?? 0.0,
      action: map['action'] as String? ?? '',
      details: map['details'] as String? ?? '',
    );
  }
}

/// Holds the full trace of priority score evolution from initial prediction to final override.
class ScoreEvolutionTrace {
  final List<ScoreEvolutionStep> steps;
  final double initialScore;
  final double finalScore;
  final String overrideTrigger; // 'none', 'expired_otp', 'expired_deadline', 'duplicate', 'completed_task', 'critical_bypass', 'policy_ceiling'

  const ScoreEvolutionTrace({
    required this.steps,
    required this.initialScore,
    required this.finalScore,
    required this.overrideTrigger,
  });

  Map<String, dynamic> toMap() {
    return {
      'steps': steps.map((s) => s.toMap()).toList(),
      'initialScore': initialScore,
      'finalScore': finalScore,
      'overrideTrigger': overrideTrigger,
    };
  }

  factory ScoreEvolutionTrace.fromMap(Map<String, dynamic> map) {
    final rawSteps = map['steps'] as List?;
    final steps = rawSteps != null
        ? rawSteps.map((s) => ScoreEvolutionStep.fromMap(s as Map<String, dynamic>)).toList()
        : <ScoreEvolutionStep>[];
    return ScoreEvolutionTrace(
      steps: steps,
      initialScore: (map['initialScore'] as num?)?.toDouble() ?? 0.0,
      finalScore: (map['finalScore'] as num?)?.toDouble() ?? 0.0,
      overrideTrigger: map['overrideTrigger'] as String? ?? 'none',
    );
  }
}

/// Data container for a single structured inference audit record.
class InferenceAuditRecord {
  final int? id;
  final String notificationId;
  final int timestamp;
  final String packageName;
  final String? classifiedCategory;
  final double? rawMlScore;
  final double? fusedScore;
  final String finalPriority;
  final String overrideTrigger;
  final int latencyMs;
  final List<FeatureAttribution> featureAttributions;
  final List<ScoreEvolutionStep> scoreEvolutionSteps;
  final DateTime createdAt;

  InferenceAuditRecord({
    this.id,
    required this.notificationId,
    required this.timestamp,
    required this.packageName,
    this.classifiedCategory,
    this.rawMlScore,
    this.fusedScore,
    required this.finalPriority,
    required this.overrideTrigger,
    required this.latencyMs,
    required this.featureAttributions,
    required this.scoreEvolutionSteps,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'notificationId': notificationId,
      'timestamp': timestamp,
      'packageName': PiiRedactor.redact(packageName),
      'classifiedCategory': classifiedCategory,
      'rawMlScore': rawMlScore,
      'fusedScore': fusedScore,
      'finalPriority': finalPriority,
      'overrideTrigger': overrideTrigger,
      'latencyMs': latencyMs,
      'featureAttributionsJson': jsonEncode(featureAttributions.map((f) => f.toMap()).toList()),
      'scoreEvolutionJson': jsonEncode(scoreEvolutionSteps.map((s) => s.toMap()).toList()),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
