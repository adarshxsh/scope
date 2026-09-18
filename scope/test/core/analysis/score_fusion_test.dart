import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  setUp(() {
    ScoreFusion.resetSettings();
  });

  group('CategoryPrecision & CategoryPrecisionMapping', () {
    test('provides correct default precision weights and Platt parameters', () {
      final mapping = CategoryPrecisionMapping();

      final finance = mapping.getPrecision('finance');
      expect(finance.alpha, equals(0.90));
      expect(finance.plattA, equals(1.2));
      expect(finance.plattB, equals(0.3));

      final promo = mapping.getPrecision('promo');
      expect(promo.alpha, equals(0.35));
      expect(promo.plattA, equals(0.8));
      expect(promo.plattB, equals(-0.5));

      final unknown = mapping.getPrecision('unknown_category');
      expect(unknown.alpha, equals(0.50));
    });

    test('parses dynamic runtime JSON calibration configuration map', () {
      final jsonConfig = {
        'finance': {'alpha': 0.95, 'a': 4.0, 'b': -0.1},
        'promo': {'alpha': 0.20, 'a': 1.5, 'b': -2.0},
      };

      final mapping = CategoryPrecisionMapping.fromMap(jsonConfig);

      expect(mapping.getPrecision('finance').alpha, equals(0.95));
      expect(mapping.getPrecision('finance').plattA, equals(4.0));
      expect(mapping.getPrecision('promo').alpha, equals(0.20));
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

  group('ScoreFusion - Dynamic Weighting & Fallback', () {
    test('dynamically adjusts score fusion when isFallback is true', () {
      final ruleMatch = MatchedRuleResult(
        ruleId: 'work_collaboration',
        category: 'msg',
        priority: 'high',
        matchedSignal: 'slack message',
      );

      final activeModelResult = AnalysisResult(
        category: 'msg',
        score: 0.90,
        engineName: 'litert_model',
        matchedSignals: [],
        latencyMs: 5,
        isFallback: false,
      );

      final fallbackModelResult = AnalysisResult(
        category: 'promo',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 1,
        isFallback: true,
      );

      final activeFused = ScoreFusion.fuse(
        ruleResult: ruleMatch,
        modelResult: activeModelResult,
      );

      final fallbackFused = ScoreFusion.fuse(
        ruleResult: ruleMatch,
        modelResult: fallbackModelResult,
      );

      expect(activeFused.score, greaterThanOrEqualTo(0.90));
      expect(fallbackFused.isFallback, isTrue);
      expect(fallbackFused.category, equals('msg'));
    });

    test('accepts explicit mlConfidence and isFallback parameters', () {
      final ruleMatch = MatchedRuleResult(
        ruleId: 'work_collaboration',
        category: 'msg',
        priority: 'high',
        matchedSignal: 'slack message',
      );

      final modelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model',
        matchedSignals: [],
        latencyMs: 5,
        isFallback: false,
      );

      final fusedOverride = ScoreFusion.fuse(
        ruleResult: ruleMatch,
        modelResult: modelResult,
        mlConfidence: 0.95,
        isFallback: false,
      );

      expect(fusedOverride.score, greaterThanOrEqualTo(0.90));

      final fusedFallbackOverride = ScoreFusion.fuse(
        ruleResult: ruleMatch,
        modelResult: modelResult,
        mlConfidence: 0.20,
        isFallback: true,
      );

      expect(fusedFallbackOverride.isFallback, isTrue);
    });

    test('parses and applies configurable weight parameters from JSON settings', () {
      const customJsonStr = '''
      {
        "rule_weight": 0.50,
        "ml_weight": 0.30,
        "policy_weight": 0.20,
        "fallback_rule_weight": 0.70,
        "fallback_ml_weight": 0.05,
        "fallback_policy_weight": 0.25
      }
      ''';

      final customSettings = ScoreFusionSettings.fromJsonString(customJsonStr);
      ScoreFusion.configure(customSettings);

      expect(ScoreFusion.settings.ruleWeight, equals(0.50));
      expect(ScoreFusion.settings.mlWeight, equals(0.30));
      expect(ScoreFusion.settings.fallbackMlWeight, equals(0.05));
    });

    test('preserves deterministic critical bypass rules with score 1.0 regardless of fallback state', () {
      final bypassRule = MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'OTP match',
      );

      final fallbackModel = AnalysisResult(
        category: 'promo',
        score: 0.10,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: bypassRule,
        modelResult: fallbackModel,
      );

      expect(fused.score, equals(1.0));
      expect(fused.category, equals('sys'));
      expect(fused.engineName, contains('rule bypass: otp_security'));
    });

    test('executes score fusion calculation in under 1ms constraint', () {
      final ruleMatch = MatchedRuleResult(
        ruleId: 'work_collaboration',
        category: 'msg',
        priority: 'high',
        matchedSignal: 'slack message',
      );

      final modelResult = AnalysisResult(
        category: 'msg',
        score: 0.85,
        engineName: 'litert_model',
        matchedSignals: [],
        latencyMs: 2,
        isFallback: false,
      );

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );
      }
      stopwatch.stop();

      final avgMs = stopwatch.elapsedMicroseconds / (100 * 1000.0);
      expect(avgMs, lessThan(1.0));
    });
  });
}
