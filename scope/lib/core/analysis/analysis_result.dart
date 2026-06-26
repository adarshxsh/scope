/// Holds the results of a single classification engine analysis step.
class AnalysisResult {
  /// The predicted semantic category (e.g. 'finance', 'msg', 'promo', etc.).
  final String category;

  /// The confidence score of the classification (0.0 to 1.0).
  final double score;

  /// Name of the engine producing the analysis ('rule_engine', 'litert_model', etc.).
  final String engineName;

  /// List of matched keywords, patterns, or signals.
  final List<String> matchedSignals;

  /// Latency of the analysis step in milliseconds.
  final int latencyMs;

  const AnalysisResult({
    required this.category,
    required this.score,
    required this.engineName,
    required this.matchedSignals,
    required this.latencyMs,
  });

  @override
  String toString() => 'AnalysisResult(category: $category, score: $score, '
      'engineName: $engineName, matchedSignals: $matchedSignals, latencyMs: ${latencyMs}ms)';
}
