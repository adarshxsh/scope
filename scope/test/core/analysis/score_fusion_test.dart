import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion', () {
    test('returns unblended rule score when modelResult.isFallback is true', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_promo_rule',
        category: 'promo',
        priority: 'low',
        matchedSignal: 'keyword match',
      );

      final fallbackModelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback active'],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: fallbackModelResult,
      );

      expect(fused.isFallback, isTrue);
      expect(fused.score, equals(0.85)); // Unblended rule score
      expect(fused.category, equals('promo'));
      expect(fused.engineName, contains('model fallback'));
    });

    test('blends scores when modelResult.isFallback is false', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_promo_rule',
        category: 'promo',
        priority: 'low',
        matchedSignal: 'keyword match',
      );

      final authenticModelResult = AnalysisResult(
        category: 'promo',
        score: 0.95,
        engineName: 'litert_model',
        matchedSignals: ['Authentic prediction'],
        latencyMs: 5,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: authenticModelResult,
      );

      expect(fused.isFallback, isFalse);
      expect(fused.score, equals(0.90)); // Blended boost
      expect(fused.category, equals('promo'));
    });
  });

  group('ExplanationGenerator', () {
    test('renders explicit fallback status when fusedResult.isFallback is true', () {
      final fallbackResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 1,
        isFallback: true,
      );

      final trace = ExplanationGenerator.generate(
        fusedResult: fallbackResult,
        features: const ExtractedFeatures(),
        priority: 'medium',
      );

      expect(trace, contains('Fallback Heuristic (Model Uninitialized)'));
      expect(trace, isNot(contains('50%')));
    });
  });
}
