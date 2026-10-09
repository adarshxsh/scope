import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/score_evolution_trace.dart';

void main() {
  group('ScoreEvolutionTrace Tests', () {
    test('serializes to map/json and deserializes correctly', () {
      const step1 = ScoreEvolutionStep(
        stageName: 'LiteRT Category Inference',
        score: 0.85,
        description: 'Categorized as finance',
      );
      const step2 = ScoreEvolutionStep(
        stageName: 'Policy Engine',
        score: 0.85,
        description: 'Resolved HIGH priority',
        trigger: 'none',
      );

      const trace = ScoreEvolutionTrace(
        steps: [step1, step2],
        finalPriority: 'high',
        finalScore: 0.85,
        overrideTrigger: 'none',
      );

      final jsonStr = trace.toJson();
      final restoredTrace = ScoreEvolutionTrace.fromJson(jsonStr);

      expect(restoredTrace.finalPriority, equals('high'));
      expect(restoredTrace.finalScore, equals(0.85));
      expect(restoredTrace.steps.length, equals(2));
      expect(restoredTrace.steps[0].stageName, equals('LiteRT Category Inference'));
    });

    test('handles malformed json gracefully', () {
      final restored = ScoreEvolutionTrace.fromJson('invalid json content');
      expect(restored.finalPriority, equals('low'));
      expect(restored.finalScore, equals(0.0));
      expect(restored.steps, isEmpty);
    });
  });
}
