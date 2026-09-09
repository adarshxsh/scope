import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/analysis/extracted_features.dart';

void main() {
  group('ExplanationGenerator Fallback Formatting Tests', () {
    test('explicitly formats fallback trace when isFallback is true', () {
      const fallbackResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback heuristic'],
        latencyMs: 1,
        isFallback: true,
        fallbackReason: 'Model asset uninitialized',
      );

      const features = ExtractedFeatures();

      final trace = ExplanationGenerator.generate(
        fusedResult: fallbackResult,
        features: features,
        priority: 'medium',
      );

      expect(trace, contains('Fallback Heuristic Active'));
      expect(trace, contains('Model asset uninitialized'));
    });

    test('formats standard confidence trace when isFallback is false', () {
      const standardResult = AnalysisResult(
        category: 'finance',
        score: 0.95,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 12,
        isFallback: false,
      );

      const features = ExtractedFeatures();

      final trace = ExplanationGenerator.generate(
        fusedResult: standardResult,
        features: features,
        priority: 'critical',
      );

      expect(trace, contains('• Confidence: **95%**.'));
      expect(trace, isNot(contains('Fallback Heuristic Active')));
    });
  });
}
