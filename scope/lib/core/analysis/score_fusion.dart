import 'dart:convert';
import 'dart:math' as math;
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

/// Domain precision weight vector and Platt sigmoidal calibration parameters for a category.
class CategoryPrecision {
  /// Precision weight factor alpha in [0.0, 1.0].
  final double alpha;

  /// Platt sigmoidal scaling parameter A (slope).
  final double plattA;

  /// Platt sigmoidal scaling parameter B (offset/intercept).
  final double plattB;

  const CategoryPrecision({
    required this.alpha,
    this.plattA = 1.0,
    this.plattB = 0.0,
  });

  factory CategoryPrecision.fromMap(Map<String, dynamic> map) {
    final alphaVal = (map['alpha'] ?? map['precision_weight'] ?? map['precisionWeight'] ?? 0.5) as num;
    final aVal = (map['a'] ?? map['A'] ?? map['platt_a'] ?? map['plattA'] ?? 1.0) as num;
    final bVal = (map['b'] ?? map['B'] ?? map['platt_b'] ?? map['plattB'] ?? 0.0) as num;

    return CategoryPrecision(
      alpha: alphaVal.toDouble().clamp(0.0, 1.0),
      plattA: aVal.toDouble(),
      plattB: bVal.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'alpha': alpha,
        'a': plattA,
        'b': plattB,
      };

  /// Calibrates a raw model score x in [0.0, 1.0] via Platt sigmoidal transformation.
  double calibrate(double rawScore) {
    if (rawScore.isNaN || rawScore.isInfinite) return 0.5;
    final clampedX = rawScore.clamp(1e-7, 1.0 - 1e-7);
    final logit = math.log(clampedX / (1.0 - clampedX));
    final z = plattA * logit + plattB;
    if (z > 20.0) return 1.0;
    if (z < -20.0) return 0.0;
    return (1.0 / (1.0 + math.exp(-z))).clamp(0.0, 1.0);
  }
}

/// Category-specific precision mapping defining precision weights (alpha)
/// and Platt scaling parameters for each notification domain.
class CategoryPrecisionMapping {
  final Map<String, CategoryPrecision> _mapping;

  static const CategoryPrecision defaultPrecision = CategoryPrecision(
    alpha: 0.50,
    plattA: 1.0,
    plattB: 0.0,
  );

  static final Map<String, CategoryPrecision> defaultMapping = {
    'finance': const CategoryPrecision(alpha: 0.90, plattA: 1.2, plattB: 0.3),
    'scholarship': const CategoryPrecision(alpha: 0.85, plattA: 1.1, plattB: 0.2),
    'health': const CategoryPrecision(alpha: 0.80, plattA: 1.1, plattB: 0.1),
    'sys': const CategoryPrecision(alpha: 0.70, plattA: 1.0, plattB: 0.0),
    'msg': const CategoryPrecision(alpha: 0.65, plattA: 1.0, plattB: 0.0),
    'email': const CategoryPrecision(alpha: 0.60, plattA: 1.0, plattB: 0.0),
    'social': const CategoryPrecision(alpha: 0.40, plattA: 0.9, plattB: -0.3),
    'promo': const CategoryPrecision(alpha: 0.35, plattA: 0.8, plattB: -0.5),
    'otp_security': const CategoryPrecision(alpha: 0.95, plattA: 1.5, plattB: 0.5),
    'otp': const CategoryPrecision(alpha: 0.95, plattA: 1.5, plattB: 0.5),
    'default': defaultPrecision,
  };

  CategoryPrecisionMapping([Map<String, CategoryPrecision>? mapping])
      : _mapping = mapping ?? Map.from(defaultMapping);

  factory CategoryPrecisionMapping.fromMap(Map<String, dynamic> map) {
    final customMapping = Map<String, CategoryPrecision>.from(defaultMapping);
    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        customMapping[key.toLowerCase().trim()] = CategoryPrecision.fromMap(value);
      } else if (value is Map) {
        customMapping[key.toLowerCase().trim()] = CategoryPrecision.fromMap(Map<String, dynamic>.from(value));
      }
    });
    return CategoryPrecisionMapping(customMapping);
  }

  CategoryPrecision getPrecision(String? category) {
    if (category == null || category.trim().isEmpty) {
      return _mapping['default'] ?? defaultPrecision;
    }
    final normalized = category.toLowerCase().trim();
    return _mapping[normalized] ?? _mapping['default'] ?? defaultPrecision;
  }

  /// Returns raw precision weight alpha in [0.0, 1.0].
  static double getPrecisionWeight(String? category) {
    if (category == null || category.trim().isEmpty) return 0.75;
    final normalized = category.toLowerCase().trim();
    final item = defaultMapping[normalized];
    return item?.alpha ?? 0.75;
  }
}

/// Applies Platt sigmoidal calibration to raw model prediction scores.
class PlattCalibrator {
  final double scale;
  final double shift;

  const PlattCalibrator({this.scale = 3.0, this.shift = -1.5});

  double calibrate(double rawScore) {
    if (rawScore.isNaN || rawScore.isInfinite) return 0.5;
    final clamped = rawScore.clamp(0.0, 1.0);
    final logit = scale * clamped + shift;
    final calibrated = 1.0 / (1.0 + math.exp(-logit));
    return calibrated.clamp(0.0, 1.0);
  }
}

/// Fuses outputs of rules and model predictions using dynamic confidence and precision weighting.
class ScoreFusion {
  static ScoreFusionSettings _currentSettings = const ScoreFusionSettings();
  static CategoryPrecisionMapping _activeMapping = CategoryPrecisionMapping();

  static ScoreFusionSettings get settings => _currentSettings;
  static CategoryPrecisionMapping get activeMapping => _activeMapping;

  /// Configures settings for score fusion.
  static void configure(ScoreFusionSettings settings) {
    _currentSettings = settings;
  }

  /// Configures category precision mapping.
  static void configurePrecisionMapping(CategoryPrecisionMapping mapping) {
    _activeMapping = mapping;
  }

  /// Configures precision mapping from JSON map.
  static void configureFromMap(Map<String, dynamic> map) {
    _activeMapping = CategoryPrecisionMapping.fromMap(map);
  }

  /// Loads settings from JSON string.
  static void loadSettings(String jsonStr) {
    _currentSettings = ScoreFusionSettings.fromJsonString(jsonStr);
  }

  /// Asynchronously loads fusion settings from assets.
  static Future<void> loadSettingsFromAsset({String path = 'assets/fusion_settings.json'}) async {
    try {
      final jsonStr = await rootBundle.loadString(path);
      loadSettings(jsonStr);
    } catch (_) {
      // Use defaults if missing
    }
  }

  /// Resets settings to default values.
  static void resetSettings() {
    _currentSettings = const ScoreFusionSettings();
    _activeMapping = CategoryPrecisionMapping();
  }

  static void resetConfig() {
    resetSettings();
  }

  /// Calibrates model score for a category using Platt sigmoidal transformation.
  static double calibrateModelScore(
    double rawScore,
    String? category, {
    CategoryPrecisionMapping? precisionMapping,
  }) {
    final mapping = precisionMapping ?? _activeMapping;
    final precision = mapping.getPrecision(category);
    return precision.calibrate(rawScore);
  }

  /// Calculates weighted score fusion of calibrated model score and rule score for a category.
  static double fuseRawScores({
    required double calibratedModelScore,
    required double ruleScore,
    String? category,
    CategoryPrecisionMapping? precisionMapping,
  }) {
    final mapping = precisionMapping ?? _activeMapping;
    final precision = mapping.getPrecision(category);
    final fused = precision.alpha * calibratedModelScore + (1.0 - precision.alpha) * ruleScore;
    return fused.clamp(0.0, 1.0);
  }

  /// Maps rule priority string to numeric rule confidence score.
  static double rulePriorityToScore(String priority) {
    switch (priority) {
      case 'critical':
        return 1.0;
      case 'high':
        return 0.85;
      case 'medium':
        return 0.50;
      case 'low':
      default:
        return 0.15;
    }
  }

  /// Fuses rule match results and model classification predictions using dynamic confidence weighting.
  static AnalysisResult fuse({
    MatchedRuleResult? ruleResult,
    required AnalysisResult modelResult,
    double? mlConfidence,
    bool? isFallback,
    ScoreFusionSettings? settings,
    PlattCalibrator? calibrator,
    CategoryPrecisionMapping? precisionMapping,
  }) {
    final activeSettings = settings ?? _currentSettings;
    final activePrecisionMapping = precisionMapping ?? _activeMapping;
    final activeCalibrator = calibrator ?? const PlattCalibrator();

    final rawMlScore = mlConfidence ?? modelResult.score;
    final sanitizedMlScore = (rawMlScore.isNaN || rawMlScore.isInfinite)
        ? 0.5
        : rawMlScore.clamp(0.0, 1.0);

    final effectiveIsFallback = isFallback ??
        modelResult.isFallback ||
        modelResult.engineName.toLowerCase().contains('fallback');

    // 1. Deterministic critical bypass rules
    if (ruleResult != null) {
      final isBypass = ruleResult.priority == 'critical' ||
          ruleResult.ruleId == 'otp_security' ||
          ruleResult.ruleId == 'finance_debit' ||
          ruleResult.ruleId == 'scholarship_portal';

      if (isBypass) {
        return AnalysisResult(
          category: ruleResult.category,
          score: 1.0,
          engineName: 'score_fusion (rule bypass: ${ruleResult.ruleId})',
          matchedSignals: [ruleResult.matchedSignal],
          latencyMs: modelResult.latencyMs,
          isFallback: effectiveIsFallback,
        );
      }
    }

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

    final category = ruleResult?.category ?? modelResult.category;
    final precisionObj = activePrecisionMapping.getPrecision(category);
    final calibratedMlScore = precisionObj.calibrate(sanitizedMlScore);

    // 2. Normal score fusion when no rule matches
    if (ruleResult == null) {
      const policyBaseScore = 0.50;
      final totalW = mlW + policyW;
      final fusedScore = totalW > 0
          ? (mlW * calibratedMlScore + policyW * policyBaseScore) / totalW
          : calibratedMlScore;

      return AnalysisResult(
        category: modelResult.category,
        score: fusedScore.clamp(0.0, 1.0),
        engineName: effectiveIsFallback ? 'score_fusion (fallback)' : modelResult.engineName,
        matchedSignals: modelResult.matchedSignals,
        latencyMs: modelResult.latencyMs,
        isFallback: effectiveIsFallback,
      );
    }

    // 3. Hybrid fusion: Both rule and model match
    final ruleBaseScore = rulePriorityToScore(ruleResult.priority);
    const policyBaseScore = 0.50;

    final modelAgrees = modelResult.category == ruleResult.category;
    final modelScoreTerm = modelAgrees ? calibratedMlScore : (1.0 - calibratedMlScore);

    final totalW = ruleW + mlW + policyW;
    double score = totalW > 0
        ? (ruleW * ruleBaseScore + mlW * modelScoreTerm + policyW * policyBaseScore) / totalW
        : ruleBaseScore;

    // Apply precision weighting adjustment
    final precisionAlpha = precisionObj.alpha;
    score = (1.0 - precisionAlpha) * score + precisionAlpha * (modelAgrees ? calibratedMlScore : score);

    if (!effectiveIsFallback) {
      if (modelAgrees && score < 0.90) {
        score = 0.90;
      } else if (!modelAgrees && score < 0.70) {
        score = 0.70;
      }
    }

    final finalScore = score.clamp(0.0, 1.0);

    return AnalysisResult(
      category: category,
      score: finalScore.isNaN || finalScore.isInfinite ? 0.85 : finalScore,
      engineName: effectiveIsFallback ? 'score_fusion (fallback heuristic)' : 'score_fusion (hybrid)',
      matchedSignals: [
        'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
        'Model predicted: ${modelResult.category} (${(sanitizedMlScore * 100).toStringAsFixed(1)}% raw, ${(calibratedMlScore * 100).toStringAsFixed(1)}% calibrated${effectiveIsFallback ? " [fallback]" : ""})',
        if (effectiveIsFallback) 'Fallback Heuristic (Model Uninitialized)',
        'Category precision weight: ${(precisionAlpha * 100).toStringAsFixed(0)}%',
      ],
      latencyMs: modelResult.latencyMs,
      isFallback: effectiveIsFallback,
    );
  }
}
