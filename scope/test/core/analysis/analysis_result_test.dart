import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';

void main() {
  group('AnalysisResult Metadata Tests', () {
    test('defaults isFallback to false and fallbackReason to null', () {
      const result = AnalysisResult(
        category: 'finance',
        score: 0.95,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 12,
      );

      expect(result.isFallback, isFalse);
      expect(result.fallbackReason, isNull);
      expect(result.toString(), contains('isFallback: false'));
    });

    test('supports explicit isFallback and fallbackReason values', () {
      const result = AnalysisResult(
        category: 'finance',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Model asset invalid or uninitialized'],
        latencyMs: 1,
        isFallback: true,
        fallbackReason: 'Model asset uninitialized',
      );

      expect(result.isFallback, isTrue);
      expect(result.fallbackReason, equals('Model asset uninitialized'));
      expect(result.toString(), contains('isFallback: true'));
      expect(result.toString(), contains('fallbackReason: Model asset uninitialized'));
    });
  });
}
