import 'dart:math' as math;
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';

/// Maps notification categories to model accuracy / precision weights.
class CategoryPrecisionMapping {
  static const Map<String, double> _defaultPrecisionMap = {
    'finance': 0.95,
    'otp_security': 0.95,
    'otp': 0.95,
    'msg': 0.85,
    'sys': 0.80,
    'promo': 0.70,
    'social': 0.65,
  };

  /// Returns category precision weight in range [0.0, 1.0]. Defaults to 0.75 for unknown categories.
  static double getPrecision(String? category) {
    if (category == null || category.trim().isEmpty) return 0.75;
    final normalized = category.toLowerCase().trim();
    return _defaultPrecisionMap[normalized] ?? 0.75;
  }
}

/// Applies Platt sigmoidal calibration to raw model prediction scores.
class PlattCalibrator {
  final double scale;
  final double shift;

  const PlattCalibrator({this.scale = 3.0, this.shift = -1.5});

  /// Calibrates raw model score using a Platt sigmoidal transformation.
  /// Handles non-finite inputs gracefully.
  double calibrate(double rawScore) {
    if (rawScore.isNaN || rawScore.isInfinite) {
      return 0.5;
    }
    final clamped = rawScore.clamp(0.0, 1.0);
    final logit = scale * clamped + shift;
    final calibrated = 1.0 / (1.0 + math.exp(-logit));
    return calibrated.clamp(0.0, 1.0);
  }
}

/// Fuses outputs of rules and model predictions.
class ScoreFusion {
  /// Fuses rule match results and model classification predictions.
  /// Applies a deterministic bypass for critical rules (fraud, OTPs, scholarships),
  /// Platt sigmoidal calibration, and category precision dynamic weighting.
  static AnalysisResult fuse({
    MatchedRuleResult? ruleResult,
    required AnalysisResult modelResult,
    PlattCalibrator calibrator = const PlattCalibrator(),
  }) {
    // 1. Sanitize model score if non-finite
    final rawModelScore = (modelResult.score.isNaN || modelResult.score.isInfinite)
        ? 0.5
        : modelResult.score.clamp(0.0, 1.0);

    final isModelFallback =
        modelResult.engineName.toLowerCase().contains('fallback');

    // 2. Check for deterministic critical bypass rules
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
          latencyMs: modelResult.latencyMs,
        );
      }
    }

    // 3. Fallback handling for uninitialized/fallback model
    if (isModelFallback) {
      if (ruleResult != null) {
        return AnalysisResult(
          category: ruleResult.category,
          score: 0.85, // Retain rule base confidence
          engineName: 'score_fusion (fallback heuristic)',
          matchedSignals: [
            'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
            'Fallback Heuristic (Model Uninitialized)',
          ],
          latencyMs: modelResult.latencyMs,
        );
      } else {
        return AnalysisResult(
          category: modelResult.category,
          score: rawModelScore,
          engineName: modelResult.engineName,
          matchedSignals: modelResult.matchedSignals,
          latencyMs: modelResult.latencyMs,
        );
      }
    }

    // 4. If no rule matches, rely on calibrated model prediction
    if (ruleResult == null) {
      final calScore = calibrator.calibrate(rawModelScore);
      return AnalysisResult(
        category: modelResult.category,
        score: calScore,
        engineName: modelResult.engineName,
        matchedSignals: modelResult.matchedSignals,
        latencyMs: modelResult.latencyMs,
      );
    }

    // 5. Dynamic hybrid fusion: Both rule and model match
    final category = ruleResult.category;
    const double ruleScore = 0.85; // Base high confidence for rule matches

    final calModelScore = calibrator.calibrate(rawModelScore);
    final categoryPrecision = CategoryPrecisionMapping.getPrecision(category);

    final modelAgrees = modelResult.category == category;
    double fusedScore;

    if (modelAgrees) {
      final wRule = 1.0 - (categoryPrecision * 0.5);
      final wModel = categoryPrecision;
      fusedScore = (wRule * ruleScore + wModel * calModelScore) / (wRule + wModel);
      if (calModelScore > 0.5) {
        fusedScore += 0.05 * categoryPrecision * calModelScore;
      }
    } else {
      final wRule = 1.0;
      final wModel = categoryPrecision * 0.5;
      fusedScore = (wRule * ruleScore + wModel * (1.0 - calModelScore)) / (wRule + wModel);
    }

    fusedScore = fusedScore.clamp(0.0, 1.0);
    if (fusedScore.isNaN || fusedScore.isInfinite) {
      fusedScore = 0.85;
    }

    return AnalysisResult(
      category: category,
      score: fusedScore,
      engineName: 'score_fusion (hybrid)',
      matchedSignals: [
        'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
        'Model predicted: ${modelResult.category} (${(rawModelScore * 100).toStringAsFixed(1)}% raw, ${(calModelScore * 100).toStringAsFixed(1)}% calibrated)',
        'Category precision weight: ${(categoryPrecision * 100).toStringAsFixed(0)}%',
      ],
      latencyMs: modelResult.latencyMs,
    );
  }
}

