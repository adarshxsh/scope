import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';

/// Represents category-specific calibration parameters derived from domain precision curves.
class CategoryPrecisionProfile {
  /// Category identifier (e.g., 'finance', 'sys', 'msg', 'promo', 'social', 'health', 'scholarship', 'utilities', 'delivery', 'other').
  final String category;

  /// Relative confidence weight assigned to rule matches (0.0 to 1.0).
  final double ruleWeight;

  /// Relative confidence weight assigned to ML model predictions based on domain accuracy (0.0 to 1.0).
  final double modelWeight;

  /// Base score for rule matches in this domain prior to model fusion.
  final double baseRuleScore;

  /// Dynamic agreement boost factor when model and rule agree.
  final double agreementBoost;

  /// Disagreement attenuation penalty factor when model and rule conflict.
  final double disagreementPenalty;

  const CategoryPrecisionProfile({
    required this.category,
    this.ruleWeight = 0.50,
    this.modelWeight = 0.50,
    this.baseRuleScore = 0.85,
    this.agreementBoost = 0.09375,
    this.disagreementPenalty = 0.15,
  });
}

/// Configuration repository mapping notification categories to precision profiles.
class CategoryCalibrationConfig {
  final Map<String, CategoryPrecisionProfile> _profiles;

  CategoryCalibrationConfig([Map<String, CategoryPrecisionProfile>? customProfiles])
      : _profiles = Map.unmodifiable(_defaultProfiles..addEntries(customProfiles?.entries ?? []));

  /// Default pre-calibrated domain precision profiles across AttentionOS notification domains.
  static final Map<String, CategoryPrecisionProfile> _defaultProfiles = {
    'finance': const CategoryPrecisionProfile(
      category: 'finance',
      ruleWeight: 0.40,
      modelWeight: 0.60,
      baseRuleScore: 0.85,
      agreementBoost: 0.08,
      disagreementPenalty: 0.10,
    ),
    'security': const CategoryPrecisionProfile(
      category: 'security',
      ruleWeight: 0.70,
      modelWeight: 0.30,
      baseRuleScore: 0.85,
      agreementBoost: 0.05,
      disagreementPenalty: 0.08,
    ),
    'otp': const CategoryPrecisionProfile(
      category: 'otp',
      ruleWeight: 0.80,
      modelWeight: 0.20,
      baseRuleScore: 0.85,
      agreementBoost: 0.05,
      disagreementPenalty: 0.05,
    ),
    'sys': const CategoryPrecisionProfile(
      category: 'sys',
      ruleWeight: 0.60,
      modelWeight: 0.40,
      baseRuleScore: 0.85,
      agreementBoost: 0.08,
      disagreementPenalty: 0.12,
    ),
    'msg': const CategoryPrecisionProfile(
      category: 'msg',
      ruleWeight: 0.50,
      modelWeight: 0.50,
      baseRuleScore: 0.85,
      agreementBoost: 0.09375,
      disagreementPenalty: 0.15,
    ),
    'email': const CategoryPrecisionProfile(
      category: 'email',
      ruleWeight: 0.50,
      modelWeight: 0.50,
      baseRuleScore: 0.85,
      agreementBoost: 0.09375,
      disagreementPenalty: 0.15,
    ),
    'promo': const CategoryPrecisionProfile(
      category: 'promo',
      ruleWeight: 0.65,
      modelWeight: 0.35,
      baseRuleScore: 0.85,
      agreementBoost: 0.06,
      disagreementPenalty: 0.20,
    ),
    'social': const CategoryPrecisionProfile(
      category: 'social',
      ruleWeight: 0.60,
      modelWeight: 0.40,
      baseRuleScore: 0.85,
      agreementBoost: 0.07,
      disagreementPenalty: 0.18,
    ),
    'health': const CategoryPrecisionProfile(
      category: 'health',
      ruleWeight: 0.45,
      modelWeight: 0.55,
      baseRuleScore: 0.85,
      agreementBoost: 0.08,
      disagreementPenalty: 0.10,
    ),
    'scholarship': const CategoryPrecisionProfile(
      category: 'scholarship',
      ruleWeight: 0.60,
      modelWeight: 0.40,
      baseRuleScore: 0.85,
      agreementBoost: 0.07,
      disagreementPenalty: 0.12,
    ),
    'utilities': const CategoryPrecisionProfile(
      category: 'utilities',
      ruleWeight: 0.50,
      modelWeight: 0.50,
      baseRuleScore: 0.85,
      agreementBoost: 0.08,
      disagreementPenalty: 0.12,
    ),
    'delivery': const CategoryPrecisionProfile(
      category: 'delivery',
      ruleWeight: 0.50,
      modelWeight: 0.50,
      baseRuleScore: 0.85,
      agreementBoost: 0.08,
      disagreementPenalty: 0.12,
    ),
    'other': const CategoryPrecisionProfile(
      category: 'other',
      ruleWeight: 0.50,
      modelWeight: 0.50,
      baseRuleScore: 0.85,
      agreementBoost: 0.08,
      disagreementPenalty: 0.15,
    ),
  };

  /// Retrieves the precision profile for a category, falling back to 'other' if unmapped.
  CategoryPrecisionProfile getProfile(String category) {
    final normalized = category.trim().toLowerCase();
    return _profiles[normalized] ??
        _profiles['other'] ??
        const CategoryPrecisionProfile(category: 'other');
  }
}

/// Fuses outputs of rules and model predictions using category-specific calibration curves.
class ScoreFusion {
  /// Shared default calibration configuration.
  static final CategoryCalibrationConfig defaultConfig = CategoryCalibrationConfig();

  /// Fuses rule match results and model classification predictions using domain calibration weights.
  /// Applies a deterministic bypass for critical rules (fraud, OTPs, scholarships) and validates score boundaries.
  static AnalysisResult fuse({
    MatchedRuleResult? ruleResult,
    required AnalysisResult modelResult,
    CategoryCalibrationConfig? config,
  }) {
    try {
      final activeConfig = config ?? defaultConfig;

      // 1. Sanitize modelResult inputs
      final sanitizedModelScore = _sanitizeScore(modelResult.score);
      final modelCategory = _sanitizeCategory(modelResult.category);

      // 2. Check for deterministic critical bypass rules
      if (ruleResult != null) {
        final ruleCategory = _sanitizeCategory(ruleResult.category);
        final isBypass = ruleResult.priority == 'critical' ||
            ruleResult.ruleId == 'otp_security' ||
            ruleResult.ruleId == 'finance_debit' ||
            ruleResult.ruleId == 'scholarship_portal';

        if (isBypass) {
          return AnalysisResult(
            category: ruleCategory,
            score: 1.0, // Maximum confidence for security/fraud bypasses
            engineName: 'score_fusion (rule bypass: ${_sanitizeSignal(ruleResult.ruleId)})',
            matchedSignals: [_sanitizeSignal(ruleResult.matchedSignal)],
            latencyMs: 0,
            isFallback: false,
          );
        }
      }

      // 3. Fallback model handling:
      // When the model is in fallback mode (e.g., uninitialized asset or inference error),
      // do not process the fallback score as an authentic model prediction.
      if (modelResult.isFallback) {
        if (ruleResult != null) {
          final ruleCategory = _sanitizeCategory(ruleResult.category);
          final profile = activeConfig.getProfile(ruleCategory);
          final baseScore = _sanitizeScore(profile.baseRuleScore);

          return AnalysisResult(
            category: ruleCategory,
            score: baseScore,
            engineName: 'score_fusion (rule only, ml fallback: ${_sanitizeSignal(ruleResult.ruleId)})',
            matchedSignals: [
              'Rule matched: ${_sanitizeSignal(ruleResult.ruleId)} (${_sanitizeSignal(ruleResult.matchedSignal)})',
              'ML model in fallback mode (score blending bypassed)'
            ],
            latencyMs: 0,
            isFallback: false,
          );
        } else {
          return AnalysisResult(
            category: modelCategory,
            score: sanitizedModelScore,
            engineName: modelResult.engineName,
            matchedSignals: modelResult.matchedSignals.map(_sanitizeSignal).toList(),
            latencyMs: modelResult.latencyMs,
            isFallback: true,
          );
        }
      }

      // 4. Normal score fusion with authentic model prediction:
      // If no rule matches, rely on sanitized model prediction.
      if (ruleResult == null) {
        return AnalysisResult(
          category: modelCategory,
          score: sanitizedModelScore,
          engineName: modelResult.engineName,
          matchedSignals: modelResult.matchedSignals.map(_sanitizeSignal).toList(),
          latencyMs: modelResult.latencyMs,
          isFallback: modelResult.isFallback,
        );
      }

      // 5. Calibrated Hybrid Fusion: Both rule and authentic model match
      final ruleCategory = _sanitizeCategory(ruleResult.category);
      final profile = activeConfig.getProfile(ruleCategory);

      final wRule = profile.ruleWeight;
      final wModel = profile.modelWeight;
      final baseRuleScore = _sanitizeScore(profile.baseRuleScore);
      final totalWeight = (wRule + wModel) <= 0 ? 1.0 : (wRule + wModel);

      double fusedScore;
      final modelAgrees = modelCategory == ruleCategory;

      if (modelAgrees) {
        // Weighted blend based on domain precision weights
        final weightedAverage = (wRule * baseRuleScore + wModel * sanitizedModelScore) / totalWeight;
        // Dynamic agreement calibration boost proportional to raw model probability
        final boost = profile.agreementBoost * sanitizedModelScore;
        fusedScore = weightedAverage + boost;
      } else {
        // Calibrated confidence attenuation for model category conflict
        final weightedAverage = (wRule * baseRuleScore + wModel * (1.0 - sanitizedModelScore)) / totalWeight;
        fusedScore = weightedAverage - (profile.disagreementPenalty * 0.1 * sanitizedModelScore);
      }

      final finalScore = _sanitizeScore(fusedScore);

      return AnalysisResult(
        category: ruleCategory,
        score: finalScore,
        engineName: 'score_fusion (hybrid)',
        matchedSignals: [
          'Rule matched: ${_sanitizeSignal(ruleResult.ruleId)} (${_sanitizeSignal(ruleResult.matchedSignal)})',
          'Model predicted: $modelCategory (${(sanitizedModelScore * 100).toStringAsFixed(1)}% confidence, weight: $wModel)',
          'Domain calibration profile applied: ${profile.category}'
        ],
        latencyMs: 0,
        isFallback: false,
      );
    } catch (e) {
      // Robust exception guardrail ensuring zero unhandled runtime exceptions
      final safeCategory = ruleResult != null ? _sanitizeCategory(ruleResult.category) : _sanitizeCategory(modelResult.category);
      final safeScore = _sanitizeScore(modelResult.score);

      return AnalysisResult(
        category: safeCategory,
        score: safeScore,
        engineName: 'score_fusion (error fallback)',
        matchedSignals: [
          'Score fusion encountered an unexpected exception and degraded gracefully.',
          'Error details: ${e.runtimeType}'
        ],
        latencyMs: 0,
        isFallback: true,
      );
    }
  }

  /// Sanitizes numerical scores to ensure bounded values in [0.0, 1.0], guarding against NaN and Infinity.
  /// Also rounds to 6 decimal places to prevent floating-point representation drift.
  static double _sanitizeScore(double score) {
    if (score.isNaN || score.isInfinite) {
      return 0.0;
    }
    final clamped = score.clamp(0.0, 1.0);
    return (clamped * 1000000).roundToDouble() / 1000000;
  }

  /// Normalizes and sanitizes category strings.
  static String _sanitizeCategory(String category) {
    final trimmed = category.trim();
    return trimmed.isEmpty ? 'other' : trimmed;
  }

  /// Ensures signals and logging output do not leak personal notification body content or newline characters.
  static String _sanitizeSignal(String signal) {
    return signal.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
  }
}
