import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/utils/pii_redactor.dart';

/// Generates a bulleted, PII-sanitized trace explaining the pipeline decisions.
class ExplanationGenerator {
  /// Builds a natural-language bulleted string describing how features, rules,
  /// categories, feature attributions, and score evolution resolved to final priority.
  static String generate({
    required AnalysisResult fusedResult,
    required ExtractedFeatures features,
    required String priority,
    GhostAIResult? ghostResult,
    List<FeatureAttribution>? featureAttributions,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Priority resolved: **${priority.toUpperCase()}**');
    buffer.writeln('• Category: Inferred semantic category is **${fusedResult.category}**.');
    buffer.writeln('• Source: Handled by **${fusedResult.engineName}**.');
    if (fusedResult.isFallback) {
      buffer.writeln('• Status: **Fallback Heuristic (ML Inference Bypassed/Failed)**.');
      buffer.writeln('• Confidence: **N/A (Fallback)**.');
    } else {
      buffer.writeln('• Confidence: **${(fusedResult.score * 100).toStringAsFixed(0)}%**.');
    }

    // Feature Signals (PII Redacted)
    if (features.otp != null) {
      buffer.writeln('• Verification Code: Sensitive passcode detected [REDACTED_OTP].');
    }
    if (features.amount != null) {
      final sanitizedAmount = PiiRedactor.redact('Rs. ${features.amount}');
      buffer.writeln('• Transaction Amount: Payment figure detected ($sanitizedAmount).');
    }
    if (features.hasDeadline) {
      buffer.writeln('• Deadline: Found urgent time-sensitivity keywords.');
    }

    // Feature Attributions Breakdown
    final attributions = featureAttributions ??
        (ghostResult != null ? ghostResult.featureAttributions : []);
    if (attributions.isNotEmpty) {
      final topInfluences = attributions
          .map((a) => '${a.displayName} (${a.direction == "positive" ? "+" : ""}${(a.weight * 100).toStringAsFixed(0)}%)')
          .join(', ');
      buffer.writeln('• Key Influences: $topInfluences.');
    }

    // Override or Score Evolution Notice
    if (ghostResult != null && ghostResult.overrideTrigger != 'none') {
      final triggerName = ghostResult.overrideTrigger.replaceAll('_', ' ').toUpperCase();
      buffer.writeln('• Override Applied: Triggered **$triggerName** guardrail.');
    }

    if (fusedResult.matchedSignals.isNotEmpty) {
      final sanitizedSignals = fusedResult.matchedSignals
          .map((s) => PiiRedactor.redact(s))
          .join('; ');
      buffer.writeln('• Matched Signals: $sanitizedSignals.');
    }

    return buffer.toString().trim();
  }
}
