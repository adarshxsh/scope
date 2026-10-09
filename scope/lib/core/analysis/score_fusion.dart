import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';

/// Configurable score fusion weight parameters.
class ScoreFusionSettings {
  final double ruleWeight;
  final double mlWeight;
  final double policyWeight;
  final double fallbackRuleWeight;
  final double fallbackMlWeight;
  final double fallbackPolicyWeight;

  const ScoreFusionSettings({
    this.ruleWeight = 0.40,
    this.mlWeight = 0.40,
    this.policyWeight = 0.20,
    this.fallbackRuleWeight = 0.60,
    this.fallbackMlWeight = 0.10,
    this.fallbackPolicyWeight = 0.30,
  });

  factory ScoreFusionSettings.fromJson(Map<String, dynamic> json) {
    return ScoreFusionSettings(
      ruleWeight: (json['rule_weight'] as num?)?.toDouble() ?? 0.40,
      mlWeight: (json['ml_weight'] as num?)?.toDouble() ?? 0.40,
      policyWeight: (json['policy_weight'] as num?)?.toDouble() ?? 0.20,
      fallbackRuleWeight: (json['fallback_rule_weight'] as num?)?.toDouble() ?? 0.60,
      fallbackMlWeight: (json['fallback_ml_weight'] as num?)?.toDouble() ?? 0.10,
      fallbackPolicyWeight: (json['fallback_policy_weight'] as num?)?.toDouble() ?? 0.30,
    );
  }

  factory ScoreFusionSettings.fromJsonString(String jsonStr) {
    final Map<String, dynamic> map = json.decode(jsonStr);
    return ScoreFusionSettings.fromJson(map);
  }

  Map<String, dynamic> toJson() => {
        'rule_weight': ruleWeight,
        'ml_weight': mlWeight,
        'policy_weight': policyWeight,
        'fallback_rule_weight': fallbackRuleWeight,
        'fallback_ml_weight': fallbackMlWeight,
        'fallback_policy_weight': fallbackPolicyWeight,
      };
}

/// Fuses outputs of rules and model predictions using dynamic confidence weighting.
class ScoreFusion {
  static ScoreFusionSettings _currentSettings = const ScoreFusionSettings();

  /// Configures the fusion engine settings.
  static void configure(ScoreFusionSettings settings) {
    _currentSettings = settings;
  }

  /// Loads settings from a JSON string.
  static void loadSettings(String jsonStr) {
    _currentSettings = ScoreFusionSettings.fromJsonString(jsonStr);
  }

  /// Asynchronously loads fusion settings from assets.
  static Future<void> loadSettingsFromAsset({String path = 'assets/fusion_settings.json'}) async {
    try {
      final jsonStr = await rootBundle.loadString(path);
      loadSettings(jsonStr);
    } catch (_) {
      // Use current default settings if asset is missing or unreadable
    }
  }

  /// Resets settings to default values.
  static void resetSettings() {
    _currentSettings = const ScoreFusionSettings();
  }

  /// Current configured settings.
  static ScoreFusionSettings get settings => _currentSettings;

  /// Fuses rule match results and model classification predictions.
  /// Accepts explicit ML confidence score and fallback flags or reads them from [modelResult].
  /// Dynamically adjusts fusion weights when [isFallback] is true (reducing ML weight to 0.10).
  static AnalysisResult fuse({
    MatchedRuleResult? ruleResult,
    required AnalysisResult modelResult,
    double? mlConfidence,
    bool? isFallback,
    ScoreFusionSettings? settings,
  }) {
    final activeSettings = settings ?? _currentSettings;
    final effectiveMlConfidence = mlConfidence ?? modelResult.score;
    final effectiveIsFallback = isFallback ?? modelResult.isFallback;

    // 1. Check for deterministic critical bypass rules
    if (ruleResult != null) {
      final isBypass = ruleResult.priority == 'critical' ||
          ruleResult.ruleId == 'otp_security' ||
          ruleResult.ruleId == 'finance_debit' ||
          ruleResult.ruleId == 'scholarship_portal';

      if (isBypass) {
        return AnalysisResult(
          category: ruleResult.category,
          score: 1.0, // Maximum confidence for security/fraud bypasses
          engineName: 'score_fusion (rule bypass: ${ruleResult.ruleId})',
          matchedSignals: [ruleResult.matchedSignal],
          latencyMs: 0,
          isFallback: effectiveIsFallback,
        );
      }
    }

    // Determine weight parameters based on fallback state
    final double ruleW;
    final double mlW;
    final double policyW;

    if (effectiveIsFallback) {
      ruleW = activeSettings.fallbackRuleWeight;
      mlW = activeSettings.fallbackMlWeight;
      policyW = activeSettings.fallbackPolicyWeight;
    } else {
      ruleW = activeSettings.ruleWeight;
      mlW = activeSettings.mlWeight;
      policyW = activeSettings.policyWeight;
    }

    // 2. Normal score fusion when no rule matches
    if (ruleResult == null) {
      const policyBaseScore = 0.50;
      final totalW = mlW + policyW;
      final fusedScore = totalW > 0
          ? (mlW * effectiveMlConfidence + policyW * policyBaseScore) / totalW
          : effectiveMlConfidence;

      return AnalysisResult(
        category: modelResult.category,
        score: fusedScore.clamp(0.0, 1.0),
        engineName: effectiveIsFallback ? 'score_fusion (fallback)' : 'score_fusion (ml_only)',
        matchedSignals: modelResult.matchedSignals,
        latencyMs: 0,
        isFallback: effectiveIsFallback,
      );
    }

    // 4. Hybrid fusion: Both rule and authentic model match
    final category = ruleResult.category;
    const ruleBaseScore = 0.85; // Base high confidence for custom rule matches
    const policyBaseScore = 0.50;

    final modelAgrees = modelResult.category == ruleResult.category;
    final modelScoreTerm = modelAgrees ? effectiveMlConfidence : (1.0 - effectiveMlConfidence);

    final totalW = ruleW + mlW + policyW;
    double score = totalW > 0
        ? (ruleW * ruleBaseScore + mlW * modelScoreTerm + policyW * policyBaseScore) / totalW
        : ruleBaseScore;

    if (!effectiveIsFallback) {
      if (modelAgrees && score < 0.90) {
        score = 0.90;
      } else if (!modelAgrees && score < 0.70) {
        score = 0.70;
      }
    }

    return AnalysisResult(
      category: category,
      score: score.clamp(0.0, 1.0),
      engineName: effectiveIsFallback ? 'score_fusion (hybrid - fallback)' : 'score_fusion (hybrid)',
      matchedSignals: [
        'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
        'Model predicted: ${modelResult.category} (${(effectiveMlConfidence * 100).toStringAsFixed(1)}% confidence${effectiveIsFallback ? " [fallback]" : ""})'
      ],
      latencyMs: 0,
      isFallback: effectiveIsFallback,
    );
  }
}
