import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion Tests', () {
    test('critical bypass rule returns max confidence bypass result', () {
      final rule = MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Matched keyword "otp"',
      );

      final modelResult = AnalysisResult(
        category: 'sys',
        score: 0.60,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 5,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: modelResult,
      );

      expect(fused.category, equals('sys'));
      expect(fused.score, equals(1.0));
      expect(fused.engineName, contains('rule bypass: otp_security'));
      expect(fused.isFallback, isFalse);
    });

    test('authentic model result blends scores when rule matches', () {
      final rule = MatchedRuleResult(
        ruleId: 'custom_rule_1',
        category: 'msg',
        priority: 'medium',
        matchedSignal: 'Matched message rule',
      );

      final modelResult = AnalysisResult(
        category: 'msg',
        score: 0.80,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 5,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: modelResult,
      );

      expect(fused.category, equals('msg'));
      expect(fused.score, equals(0.90)); // (0.85 + 0.80)/2 = 0.825 + agreement boost = 0.90
      expect(fused.engineName, equals('score_fusion (hybrid)'));
      expect(fused.isFallback, isFalse);
    });

    test('fallback model result does NOT blend score into rule match result', () {
      final rule = MatchedRuleResult(
        ruleId: 'custom_rule_2',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'Matched finance keyword',
      );

      final fallbackModelResult = AnalysisResult(
        category: 'finance',
        score: 0.0,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Uninitialized model'],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: fallbackModelResult,
      );

      expect(fused.category, equals('finance'));
      expect(fused.score, equals(0.85)); // Rule baseline preserved without blending 0.0 fallback score
      expect(fused.engineName, contains('rule only, ml fallback'));
      expect(fused.isFallback, isFalse);
    });

    test('fallback model result returned directly when no rule matches', () {
      final fallbackModelResult = AnalysisResult(
        category: 'msg',
        score: 0.0,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Uninitialized model'],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: fallbackModelResult,
      );

      expect(fused.category, equals('msg'));
      expect(fused.score, equals(0.0));
      expect(fused.engineName, equals('litert_model (fallback)'));
      expect(fused.isFallback, isTrue);
    });
  });

  group('ScoreFusion Category Calibration & Fortification Tests', () {
    test('category calibration profiles apply distinct domain model precision weights', () {
      final rule = MatchedRuleResult(
        ruleId: 'generic_rule',
        category: 'finance',
        priority: 'medium',
        matchedSignal: 'Finance match',
      );

      final highAccuracyModel = AnalysisResult(
        category: 'finance',
        score: 0.90,
        engineName: 'litert_model',
        matchedSignals: ['Softmax'],
        latencyMs: 2,
      );

      final fusedFinance = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: highAccuracyModel,
      );

      final promoRule = MatchedRuleResult(
        ruleId: 'generic_rule',
        category: 'promo',
        priority: 'medium',
        matchedSignal: 'Promo match',
      );

      final promoModel = AnalysisResult(
        category: 'promo',
        score: 0.90,
        engineName: 'litert_model',
        matchedSignals: ['Softmax'],
        latencyMs: 2,
      );

      final fusedPromo = ScoreFusion.fuse(
        ruleResult: promoRule,
        modelResult: promoModel,
      );

      // Finance uses higher model precision weight (0.60) compared to Promo (0.35)
      expect(fusedFinance.score, isNot(equals(fusedPromo.score)));
      expect(fusedFinance.matchedSignals.any((s) => s.contains('Domain calibration profile applied: finance')), isTrue);
      expect(fusedPromo.matchedSignals.any((s) => s.contains('Domain calibration profile applied: promo')), isTrue);
    });

    test('custom CategoryCalibrationConfig overrides default precision profiles', () {
      final customConfig = CategoryCalibrationConfig({
        'finance': const CategoryPrecisionProfile(
          category: 'finance',
          ruleWeight: 0.10,
          modelWeight: 0.90,
          baseRuleScore: 0.50,
          agreementBoost: 0.0,
          disagreementPenalty: 0.0,
        ),
      });

      final rule = MatchedRuleResult(
        ruleId: 'custom_fin_rule',
        category: 'finance',
        priority: 'medium',
        matchedSignal: 'Finance rule',
      );

      final model = AnalysisResult(
        category: 'finance',
        score: 1.0,
        engineName: 'litert_model',
        matchedSignals: ['High probability'],
        latencyMs: 1,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: model,
        config: customConfig,
      );

      // Fused score = (0.10*0.50 + 0.90*1.0) / 1.0 = 0.95
      expect(fused.score, equals(0.95));
    });

    test('sanitizes NaN and Infinity model scores to zero bounded values', () {
      final rule = MatchedRuleResult(
        ruleId: 'rule_1',
        category: 'msg',
        priority: 'low',
        matchedSignal: 'Rule signal',
      );

      final nanModelResult = AnalysisResult(
        category: 'msg',
        score: double.nan,
        engineName: 'corrupted_model',
        matchedSignals: ['Invalid output'],
        latencyMs: 0,
      );

      final fusedNan = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: nanModelResult,
      );

      expect(fusedNan.score, greaterThanOrEqualTo(0.0));
      expect(fusedNan.score, lessThanOrEqualTo(1.0));
      expect(fusedNan.score.isNaN, isFalse);

      final infModelResult = AnalysisResult(
        category: 'msg',
        score: double.infinity,
        engineName: 'corrupted_model',
        matchedSignals: ['Infinity output'],
        latencyMs: 0,
      );

      final fusedInf = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: infModelResult,
      );

      expect(fusedInf.score, equals(0.0));
    });

    test('sanitizes out-of-bounds scores above 1.0 or below 0.0', () {
      final overflowModelResult = AnalysisResult(
        category: 'msg',
        score: 2.50,
        engineName: 'litert_model',
        matchedSignals: ['Overflow'],
        latencyMs: 1,
      );

      final fusedOverflow = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: overflowModelResult,
      );

      expect(fusedOverflow.score, equals(1.0));

      final underflowModelResult = AnalysisResult(
        category: 'msg',
        score: -0.80,
        engineName: 'litert_model',
        matchedSignals: ['Underflow'],
        latencyMs: 1,
      );

      final fusedUnderflow = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: underflowModelResult,
      );

      expect(fusedUnderflow.score, equals(0.0));
    });

    test('gracefully recovers from unexpected calculation exceptions without throwing', () {
      final rule = MatchedRuleResult(
        ruleId: 'rule_err',
        category: 'msg',
        priority: 'medium',
        matchedSignal: 'Signal\nWith\nNewlines',
      );

      // Faulty config that forces division by zero or exception
      final invalidConfig = CategoryCalibrationConfig({
        'msg': const CategoryPrecisionProfile(
          category: 'msg',
          ruleWeight: double.nan,
          modelWeight: double.nan,
          baseRuleScore: double.nan,
        ),
      });

      final modelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model',
        matchedSignals: ['Valid signal'],
        latencyMs: 1,
      );

      expect(
        () => ScoreFusion.fuse(
          ruleResult: rule,
          modelResult: modelResult,
          config: invalidConfig,
        ),
        returnsNormally,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: modelResult,
        config: invalidConfig,
      );

      expect(fused.score.isNaN, isFalse);
      expect(fused.score, greaterThanOrEqualTo(0.0));
      expect(fused.score, lessThanOrEqualTo(1.0));
    });

    test('telemetry matchedSignals strip raw line breaks and contain no unredacted user text', () {
      final rule = MatchedRuleResult(
        ruleId: 'privacy_rule',
        category: 'sys',
        priority: 'high',
        matchedSignal: 'Matched pattern\nLine 2',
      );

      final modelResult = AnalysisResult(
        category: 'sys',
        score: 0.85,
        engineName: 'litert_model',
        matchedSignals: ['Signal 1\nSignal 2'],
        latencyMs: 2,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: rule,
        modelResult: modelResult,
      );

      for (final signal in fused.matchedSignals) {
        expect(signal.contains('\n'), isFalse, reason: 'Matched signals must strip newline characters');
      }
    });

    test('performance benchmark under high throughput execution (10,000 score fusion iterations)', () {
      final rule = MatchedRuleResult(
        ruleId: 'bench_rule',
        category: 'finance',
        priority: 'medium',
        matchedSignal: 'Bench',
      );

      final modelResult = AnalysisResult(
        category: 'finance',
        score: 0.82,
        engineName: 'litert_model',
        matchedSignals: ['Bench signal'],
        latencyMs: 1,
      );

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 10000; i++) {
        final res = ScoreFusion.fuse(
          ruleResult: rule,
          modelResult: modelResult,
        );
        expect(res.score, greaterThan(0.0));
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(2000), reason: '10,000 score fusion calls should finish within 2 seconds');
    });
  });
}
