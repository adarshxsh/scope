import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';

/// Fuses outputs of rules and model predictions.
class ScoreFusion {
  /// Fuses rule match results and model classification predictions.
  /// Applies a deterministic bypass for critical rules (fraud, OTPs, scholarships).
  static AnalysisResult fuse({
    MatchedRuleResult? ruleResult,
    required AnalysisResult modelResult,
  }) {
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

    // 2. Normal score fusion
    // If no rule matches, rely on the model prediction
    if (ruleResult == null) {
      return modelResult;
    }

    // 3. Hybrid fusion: Both rule and model match
    final category = ruleResult.category;
    double score = 0.85; // Base high confidence for custom rule matches

    final modelAgrees = modelResult.category == ruleResult.category;
    if (modelAgrees) {
      // Confidence boost if both agree
      score = (score + modelResult.score) / 2.0;
      if (score < 0.90) score = 0.90;
    } else {
      // Slight confidence reduction if they conflict, but rule still wins
      score = (score + (1.0 - modelResult.score)) / 2.0;
      if (score < 0.70) score = 0.70;
    }

    return AnalysisResult(
      category: category,
      score: score,
      engineName: 'score_fusion (hybrid)',
      matchedSignals: [
        'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
        'Model predicted: ${modelResult.category} (${(modelResult.score * 100).toStringAsFixed(1)}% confidence)'
      ],
      latencyMs: 0,
    );
  }
}
