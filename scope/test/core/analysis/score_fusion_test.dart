import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion Fallback Handling Tests', () {
    test('returns pure rule score (0.85) without blending 0.50 score when model is in fallback', () {
      const fallbackModelResult = AnalysisResult(
        category: 'finance',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback heuristic'],
        latencyMs: 1,
        isFallback: true,
        fallbackReason: 'Model asset uninitialized',
      );

      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_finance_rule',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'Keywords matched',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: fallbackModelResult,
      );

      expect(fused.score, equals(0.85)); // Not (0.85 + 0.50) / 2 = 0.675 or 0.90
      expect(fused.isFallback, isTrue);
      expect(fused.fallbackReason, equals('Model asset uninitialized'));
      expect(fused.engineName, equals('score_fusion (rule fallback)'));
    });

    test('returns pure model fallback result when no rule matches and model is in fallback', () {
      const fallbackModelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback heuristic'],
        latencyMs: 2,
        isFallback: true,
        fallbackReason: 'Model asset uninitialized',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: fallbackModelResult,
      );

      expect(fused.category, equals('msg'));
      expect(fused.score, equals(0.50));
      expect(fused.isFallback, isTrue);
      expect(fused.fallbackReason, equals('Model asset uninitialized'));
    });

    test('preserves critical rule bypass during ML fallback', () {
      const fallbackModelResult = AnalysisResult(
        category: 'finance',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback heuristic'],
        latencyMs: 1,
        isFallback: true,
        fallbackReason: 'Model asset uninitialized',
      );

      final criticalRule = MatchedRuleResult(
        ruleId: 'finance_debit',
        category: 'finance',
        priority: 'critical',
        matchedSignal: 'Debit keyword found',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: criticalRule,
        modelResult: fallbackModelResult,
      );

      expect(fused.score, equals(1.0));
      expect(fused.engineName, contains('rule bypass: finance_debit'));
      expect(fused.isFallback, isTrue);
    });

    test('blends scores as normal when model is authentic (not fallback)', () {
      const authenticModelResult = AnalysisResult(
        category: 'finance',
        score: 0.92,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 15,
        isFallback: false,
      );

      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_finance_rule',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'Keywords matched',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: authenticModelResult,
      );

      expect(fused.score, equals(0.90)); // Boost floor of 0.90 when rule and model agree
      expect(fused.isFallback, isFalse);
      expect(fused.engineName, equals('score_fusion (hybrid)'));
    });
  });
}
