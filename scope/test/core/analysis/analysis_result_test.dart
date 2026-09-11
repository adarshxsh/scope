import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';

void main() {
  group('AnalysisResult', () {
    test('defaults isFallback property to false for backward compatibility', () {
      final result = AnalysisResult(
        category: 'msg',
        score: 0.8,
        engineName: 'test_engine',
        matchedSignals: [],
        latencyMs: 10,
      );

      expect(result.isFallback, isFalse);
      expect(result.toString(), contains('isFallback: false'));
    });

    test('accepts explicit isFallback parameter when true', () {
      final result = AnalysisResult(
        category: 'sys',
        score: 0.5,
        engineName: 'fallback_engine',
        matchedSignals: [],
        latencyMs: 5,
        isFallback: true,
      );

      expect(result.isFallback, isTrue);
      expect(result.toString(), contains('isFallback: true'));
    });
  });
}
