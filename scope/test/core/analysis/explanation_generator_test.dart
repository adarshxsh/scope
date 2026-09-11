import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/analysis/extracted_features.dart';

void main() {
  group('ExplanationGenerator', () {
    test('formats explanation trace with [Fallback Execution] tag when isFallback is true', () {
      final fusedResult = AnalysisResult(
        category: 'finance',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback signal'],
        latencyMs: 1,
        isFallback: true,
      );

      final features = ExtractedFeatures();

      final explanation = ExplanationGenerator.generate(
        fusedResult: fusedResult,
        features: features,
        priority: 'medium',
      );

      expect(explanation, contains('• Confidence: [Fallback Execution].'));
      expect(explanation, isNot(contains('• Confidence: **50%**.')));
    });

    test('formats explanation trace with confidence percentage when isFallback is false', () {
      final fusedResult = AnalysisResult(
        category: 'finance',
        score: 0.92,
        engineName: 'litert_model',
        matchedSignals: ['Model signal'],
        latencyMs: 5,
        isFallback: false,
      );

      final features = ExtractedFeatures();

      final explanation = ExplanationGenerator.generate(
        fusedResult: fusedResult,
        features: features,
        priority: 'high',
      );

      expect(explanation, contains('• Confidence: **92%**.'));
      expect(explanation, isNot(contains('[Fallback Execution]')));
    });
  });
}
