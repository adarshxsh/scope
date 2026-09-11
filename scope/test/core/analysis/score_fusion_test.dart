import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion', () {
    test('bypasses model score blending when modelResult.isFallback is true', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_rule_1',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'keyword match',
      );

      final modelResult = AnalysisResult(
        category: 'promo', // Disagrees with rule category
        score: 0.50, // Static fallback score
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Model asset invalid or uninitialized'],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: modelResult,
      );

      // Score fusion should bypass model blending and preserve rule score (0.85)
      expect(fused.score, equals(0.85));
      expect(fused.category, equals('finance'));
      expect(fused.isFallback, isTrue);
      expect(fused.matchedSignals, contains(contains('Model score blending bypassed')));
    });

    test('performs normal score blending when modelResult.isFallback is false', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_rule_1',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'keyword match',
      );

      final modelResult = AnalysisResult(
        category: 'finance', // Agrees with rule category
        score: 0.95,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 5,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: modelResult,
      );

      // (0.85 + 0.95) / 2.0 = 0.90
      expect(fused.score, equals(0.90));
      expect(fused.category, equals('finance'));
      expect(fused.isFallback, isFalse);
    });

    test('returns modelResult directly when ruleResult is null', () {
      final modelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback'],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: modelResult,
      );

      expect(fused, equals(modelResult));
      expect(fused.isFallback, isTrue);
    });
  });
}
