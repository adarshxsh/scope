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
          isFallback: modelResult.isFallback,
          fallbackReason: modelResult.fallbackReason,
        );
      }
    }

    // 2. Fallback execution handling
    // If the ML model is in fallback mode, skip mathematical confidence blending
    if (modelResult.isFallback) {
      if (ruleResult != null) {
        return AnalysisResult(
          category: ruleResult.category,
          score: 0.85, // Pure rule confidence, no model score blending
          engineName: 'score_fusion (rule fallback)',
          matchedSignals: [
            'Rule matched: ${ruleResult.ruleId} (${ruleResult.matchedSignal})',
            'ML model in fallback mode: ${modelResult.fallbackReason ?? "Fallback active"}'
          ],
          latencyMs: 0,
          isFallback: true,
          fallbackReason: modelResult.fallbackReason,
        );
      }
      return modelResult;
    }

    // 3. Normal score fusion when model is not in fallback mode
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
