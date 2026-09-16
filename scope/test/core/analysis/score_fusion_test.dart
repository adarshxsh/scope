import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('CategoryPrecisionMapping', () {
    test('returns correct precision for known categories', () {
      expect(CategoryPrecisionMapping.getPrecision('finance'), equals(0.95));
      expect(CategoryPrecisionMapping.getPrecision('otp'), equals(0.95));
      expect(CategoryPrecisionMapping.getPrecision('msg'), equals(0.85));
      expect(CategoryPrecisionMapping.getPrecision('sys'), equals(0.80));
      expect(CategoryPrecisionMapping.getPrecision('promo'), equals(0.70));
      expect(CategoryPrecisionMapping.getPrecision('social'), equals(0.65));
    });

    test('returns default precision for unknown or null categories', () {
      expect(CategoryPrecisionMapping.getPrecision('unknown_cat'), equals(0.75));
      expect(CategoryPrecisionMapping.getPrecision(null), equals(0.75));
      expect(CategoryPrecisionMapping.getPrecision(''), equals(0.75));
    });
  });

  group('PlattCalibrator', () {
    const calibrator = PlattCalibrator(scale: 3.0, shift: -1.5);

    test('calibrates raw scores continuously', () {
      final calMid = calibrator.calibrate(0.5);
      expect(calMid, closeTo(0.5, 0.001));

      final calHigh = calibrator.calibrate(1.0);
      expect(calHigh, greaterThan(0.8));
      expect(calHigh, lessThanOrEqualTo(1.0));

      final calLow = calibrator.calibrate(0.0);
      expect(calLow, greaterThanOrEqualTo(0.0));
      expect(calLow, lessThan(0.3));
    });

    test('handles non-finite and out-of-bounds inputs gracefully', () {
      expect(calibrator.calibrate(double.nan), equals(0.5));
      expect(calibrator.calibrate(double.infinity), equals(0.5));
      expect(calibrator.calibrate(double.negativeInfinity), equals(0.5));
      expect(calibrator.calibrate(-0.5), closeTo(calibrator.calibrate(0.0), 0.001));
      expect(calibrator.calibrate(1.5), closeTo(calibrator.calibrate(1.0), 0.001));
    });
  });

  group('ScoreFusion', () {
    const modelResultFinance = AnalysisResult(
      category: 'finance',
      score: 0.90,
      engineName: 'litert_model',
      matchedSignals: ['finance_keyword'],
      latencyMs: 12,
    );

    const modelResultPromo = AnalysisResult(
      category: 'promo',
      score: 0.80,
      engineName: 'litert_model',
      matchedSignals: ['promo_keyword'],
      latencyMs: 15,
    );

    test('bypasses fusion for critical rules', () {
      const criticalRule = MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'finance',
        priority: 'critical',
        matchedSignal: 'OTP detected',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: criticalRule,
        modelResult: modelResultFinance,
      );

      expect(fused.score, equals(1.0));
      expect(fused.category, equals('finance'));
      expect(fused.engineName, contains('rule bypass: otp_security'));
    });

    test('bypasses fusion when model is in fallback', () {
      const customRule = MatchedRuleResult(
        ruleId: 'rlhf-custom-1',
        category: 'msg',
        priority: 'high',
        matchedSignal: 'keyword: hello',
      );

      const fallbackModelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 5,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRule,
        modelResult: fallbackModelResult,
      );

      expect(fused.score, equals(0.85));
      expect(fused.category, equals('msg'));
      expect(fused.engineName, equals('score_fusion (fallback heuristic)'));
      expect(fused.matchedSignals, contains('Fallback Heuristic (Model Uninitialized)'));
    });

    test('uses calibrated model prediction when no rule matches', () {
      final fused = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: modelResultFinance,
      );

      expect(fused.category, equals('finance'));
      expect(fused.score, greaterThan(0.0));
      expect(fused.score, lessThanOrEqualTo(1.0));
      expect(fused.engineName, equals('litert_model'));
    });

    test('fuses agreed rule and model results with category precision weighting', () {
      const customRule = MatchedRuleResult(
        ruleId: 'rlhf-custom-2',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'keyword: payment',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRule,
        modelResult: modelResultFinance,
      );

      expect(fused.category, equals('finance'));
      expect(fused.score, greaterThan(0.70));
      expect(fused.score, lessThanOrEqualTo(1.0));
      expect(fused.engineName, equals('score_fusion (hybrid)'));
      expect(fused.matchedSignals.length, equals(3));
      expect(fused.matchedSignals.last, contains('Category precision weight: 95%'));
    });

    test('fuses conflicting rule and model results gracefully', () {
      const customRule = MatchedRuleResult(
        ruleId: 'rlhf-custom-3',
        category: 'promo',
        priority: 'medium',
        matchedSignal: 'keyword: discount',
      );

      // Model predicted finance, rule matched promo
      final fused = ScoreFusion.fuse(
        ruleResult: customRule,
        modelResult: modelResultFinance,
      );

      expect(fused.category, equals('promo'));
      expect(fused.score, greaterThan(0.0));
      expect(fused.score, lessThan(0.85)); // Conflict reduces rule confidence
      expect(fused.engineName, equals('score_fusion (hybrid)'));
      expect(fused.matchedSignals.last, contains('Category precision weight: 70%'));
    });

    test('handles non-finite model scores safely without uncaught exceptions', () {
      const nanModelResult = AnalysisResult(
        category: 'sys',
        score: double.nan,
        engineName: 'litert_model',
        matchedSignals: [],
        latencyMs: 10,
      );

      const customRule = MatchedRuleResult(
        ruleId: 'rlhf-custom-4',
        category: 'sys',
        priority: 'medium',
        matchedSignal: 'sys alert',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRule,
        modelResult: nanModelResult,
      );

      expect(fused.score.isNaN, isFalse);
      expect(fused.score, greaterThanOrEqualTo(0.0));
      expect(fused.score, lessThanOrEqualTo(1.0));
    });
  });
}
