import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion', () {
    test(
      'bypasses hybrid score blending when modelResult.isFallback is true',
      () {
        final ruleResult = const MatchedRuleResult(
          ruleId: 'promo_discount',
          category: 'promo',
          priority: 'low',
          matchedSignal: 'Matched keyword discount',
        );

        final fallbackModelResult = const AnalysisResult(
          category: 'promo',
          score: 0.0,
          engineName: 'litert_model (fallback)',
          matchedSignals: ['Model asset invalid'],
          latencyMs: 5,
          isFallback: true,
        );

        final fused = ScoreFusion.fuse(
          ruleResult: ruleResult,
          modelResult: fallbackModelResult,
        );

        expect(fused.category, equals('promo'));
        expect(fused.score, equals(0.85)); // Unblended rule matching score
        expect(fused.isFallback, isTrue);
      },
    );

    test('blends scores when modelResult.isFallback is false', () {
      final ruleResult = const MatchedRuleResult(
        ruleId: 'promo_discount',
        category: 'promo',
        priority: 'low',
        matchedSignal: 'Matched keyword discount',
      );

      final validModelResult = const AnalysisResult(
        category: 'promo',
        score: 0.90,
        engineName: 'litert_model',
        matchedSignals: ['Softmax'],
        latencyMs: 12,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: validModelResult,
      );

      expect(fused.category, equals('promo'));
      // (0.85 + 0.90) / 2 = 0.875, clamped to min 0.90 since model agrees
      expect(fused.score, equals(0.90));
      expect(fused.isFallback, isFalse);
    });

    test('returns fallback model result directly when ruleResult is null', () {
      final fallbackModelResult = const AnalysisResult(
        category: 'finance',
        score: 0.0,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback heuristic'],
        latencyMs: 2,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: fallbackModelResult,
      );

      expect(fused.category, equals('finance'));
      expect(fused.score, equals(0.0));
      expect(fused.isFallback, isTrue);
    });
  });
}
