import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/analysis/score_evolution_trace.dart';

/// Generates a bulleted trace explaining the pipeline decisions.
class ExplanationGenerator {
  /// Builds a natural-language bulleted string describing how features, rules,
  /// and categories resolved to the final priority.
  static String generate({
    required AnalysisResult fusedResult,
    required ExtractedFeatures features,
    required String priority,
    List<FeatureAttribution>? attributions,
    ScoreEvolutionTrace? scoreTrace,
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

    if (features.otp != null) {
      buffer.writeln('• OTP Code: Found verification code **${FeatureAttributionCalculator.sanitizeText(features.otp!)}**.');
    }
    if (features.amount != null) {
      buffer.writeln('• Amount: Found transaction amount **Rs. ${features.amount}**.');
    }
    if (features.hasDeadline) {
      buffer.writeln('• Deadline: Found urgent timing keywords.');
    }

    if (attributions != null && attributions.isNotEmpty) {
      buffer.writeln('• Feature Attributions:');
      for (final attr in attributions.take(3)) {
        final sign = attr.influence >= 0 ? '+' : '';
        buffer.writeln('  - ${attr.featureName}: $sign${(attr.influence * 100).toStringAsFixed(0)}% (${attr.description})');
      }
    }

    if (scoreTrace != null && scoreTrace.overrideTrigger != null && scoreTrace.overrideTrigger != 'none') {
      buffer.writeln('• Override Applied: **${scoreTrace.overrideTrigger}**');
    }

    if (fusedResult.matchedSignals.isNotEmpty) {
      buffer.writeln('• matchedSignals: ${fusedResult.matchedSignals.join("; ")}.');
    }

    return buffer.toString().trim();
  }
}
