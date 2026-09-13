import 'dart:math' as math;
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';

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

  Map<String, dynamic> toMap() {
    return {
      'alpha': alpha,
      'a': plattA,
      'b': plattB,
    };
  }

  /// Calibrates a raw model score x in [0.0, 1.0] via Platt sigmoidal transformation:
  /// sigma(A * logit(x) + B), where logit(x) = ln(x / (1 - x)).
  double calibrate(double rawScore) {
    final clampedX = rawScore.clamp(1e-7, 1.0 - 1e-7);
    final logit = math.log(clampedX / (1.0 - clampedX));
    final z = plattA * logit + plattB;
    if (z > 20.0) return 1.0;
    if (z < -20.0) return 0.0;
    return 1.0 / (1.0 + math.exp(-z));
  }
}

/// Category-specific precision mapping defining precision weights (alpha)
/// and Platt scaling parameters (A_cat, B_cat) for each notification domain.
class CategoryPrecisionMapping {
  final Map<String, CategoryPrecision> _mapping;

  static const CategoryPrecision defaultPrecision = CategoryPrecision(
    alpha: 0.50,
    plattA: 1.0,
    plattB: 0.0,
  );

  /// Default baseline precision weight vectors and Platt calibration parameters.
  static final Map<String, CategoryPrecision> defaultMapping = {
    'finance': const CategoryPrecision(alpha: 0.90, plattA: 1.2, plattB: 0.3),
    'scholarship': const CategoryPrecision(alpha: 0.85, plattA: 1.1, plattB: 0.2),
    'health': const CategoryPrecision(alpha: 0.80, plattA: 1.1, plattB: 0.1),
    'sys': const CategoryPrecision(alpha: 0.70, plattA: 1.0, plattB: 0.0),
    'msg': const CategoryPrecision(alpha: 0.65, plattA: 1.0, plattB: 0.0),
    'email': const CategoryPrecision(alpha: 0.60, plattA: 1.0, plattB: 0.0),
    'social': const CategoryPrecision(alpha: 0.40, plattA: 0.9, plattB: -0.3),
    'promo': const CategoryPrecision(alpha: 0.35, plattA: 0.8, plattB: -0.5),
    'default': defaultPrecision,
  };

  CategoryPrecisionMapping([Map<String, CategoryPrecision>? mapping])
      : _mapping = mapping ?? Map.from(defaultMapping);

  factory CategoryPrecisionMapping.fromMap(Map<String, dynamic> map) {
    final customMapping = Map<String, CategoryPrecision>.from(defaultMapping);
    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        customMapping[key] = CategoryPrecision.fromMap(value);
      } else if (value is Map) {
        customMapping[key] = CategoryPrecision.fromMap(Map<String, dynamic>.from(value));
      }
    });
    return CategoryPrecisionMapping(customMapping);
  }

  CategoryPrecision getPrecision(String? category) {
    if (category == null) return _mapping['default'] ?? defaultPrecision;
    return _mapping[category] ?? _mapping['default'] ?? defaultPrecision;
  }
}

/// Fuses outputs of rules and model predictions using dynamic precision weight vectors
/// and Platt sigmoidal calibration curves.
class ScoreFusion {
  static CategoryPrecisionMapping _activeMapping = CategoryPrecisionMapping();

  /// Gets the currently active global category precision mapping.
  static CategoryPrecisionMapping get activeMapping => _activeMapping;

  /// Configures the active category precision mapping from runtime configuration assets.
  static void configure(CategoryPrecisionMapping mapping) {
    _activeMapping = mapping;
  }

  /// Configures category precision mapping from a JSON map (e.g. from model assets).
  static void configureFromMap(Map<String, dynamic> map) {
    _activeMapping = CategoryPrecisionMapping.fromMap(map);
  }

  /// Resets configuration to default precision mapping.
  static void resetConfig() {
    _activeMapping = CategoryPrecisionMapping();
  }

  /// Calibrates a raw model score for a category using Platt sigmoidal transformation.
  static double calibrateModelScore(
    double rawScore,
    String? category, {
    CategoryPrecisionMapping? precisionMapping,
  }) {
    final mapping = precisionMapping ?? _activeMapping;
    final precision = mapping.getPrecision(category);
    return precision.calibrate(rawScore);
  }

  /// Calculates weighted score fusion of calibrated model score and rule score for a category:
  /// S_fused = alpha_cat * S_model,calibrated + (1 - alpha_cat) * S_rule
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

  /// Maps rule priority string to numeric rule confidence score S_rule.
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

  /// Fuses rule match results and model classification predictions.
  /// Applies a deterministic bypass for critical security rules (OTP, debit, scholarship).
  static AnalysisResult fuse({
    MatchedRuleResult? ruleResult,
    required AnalysisResult modelResult,
    CategoryPrecisionMapping? precisionMapping,
  }) {
    final mapping = precisionMapping ?? _activeMapping;

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
        );
      }
    }

    // 2. Normal score fusion - if no rule matches, rely on calibrated model prediction
    if (ruleResult == null) {
      final calibratedScore = calibrateModelScore(
        modelResult.score,
        modelResult.category,
        precisionMapping: mapping,
      );
      return AnalysisResult(
        category: modelResult.category,
        score: calibratedScore,
        engineName: modelResult.engineName,
        matchedSignals: modelResult.matchedSignals,
        latencyMs: modelResult.latencyMs,
      );
    }

    // 3. Dynamic Category Precision Fusion: Both rule and model match
    final category = ruleResult.category;
    final precision = mapping.getPrecision(category);

    final calibratedModelScore = precision.calibrate(modelResult.score);
    final ruleScore = rulePriorityToScore(ruleResult.priority);

    // Dynamic precision weighted fusion:
    // S_fused = alpha_cat * S_model,calibrated + (1 - alpha_cat) * S_rule
    final score = fuseRawScores(
      calibratedModelScore: calibratedModelScore,
      ruleScore: ruleScore,
      category: category,
      precisionMapping: mapping,
    );

    return AnalysisResult(
      category: category,
      score: score,
      engineName: 'score_fusion (hybrid)',
      matchedSignals: [
        'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
        'Model predicted: ${modelResult.category} (${(modelResult.score * 100).toStringAsFixed(1)}% confidence, calibrated: ${(calibratedModelScore * 100).toStringAsFixed(1)}%)',
        'Category precision weight (alpha): ${precision.alpha.toStringAsFixed(2)}',
      ],
      latencyMs: 0,
    );
  }
}
