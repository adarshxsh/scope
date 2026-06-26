import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';

/// Generates a bulleted trace explaining the pipeline decisions.
class ExplanationGenerator {
  /// Builds a natural-language bulleted string describing how features, rules,
  /// and categories resolved to the final priority.
  static String generate({
    required AnalysisResult fusedResult,
    required ExtractedFeatures features,
    required String priority,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Priority resolved: **${priority.toUpperCase()}**');
    buffer.writeln('• Category: Inferred semantic category is **${fusedResult.category}**.');
    buffer.writeln('• Source: Handled by **${fusedResult.engineName}**.');
    buffer.writeln('• Confidence: **${(fusedResult.score * 100).toStringAsFixed(0)}%**.');

    if (features.otp != null) {
      buffer.writeln('• OTP Code: Found verification code **${features.otp}**.');
    }
    if (features.amount != null) {
      buffer.writeln('• Amount: Found transaction amount **Rs. ${features.amount}**.');
    }
    if (features.hasDeadline) {
      buffer.writeln('• Deadline: Found urgent timing keywords.');
    }

    if (fusedResult.matchedSignals.isNotEmpty) {
      buffer.writeln('• matchedSignals: ${fusedResult.matchedSignals.join("; ")}.');
    }

    return buffer.toString().trim();
  }
}
