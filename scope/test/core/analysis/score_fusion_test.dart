import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  setUp(() {
    ScoreFusion.resetSettings();
  });

  group('ScoreFusion - Dynamic Weighting & Fallback', () {
    test('dynamically reduces ML weight from 0.40 to 0.10 when isFallback is true', () {
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

      // In active mode: rule(0.40)*0.85 + ml(0.40)*0.90 + policy(0.20)*0.50 = 0.80 -> clamped/boosted to >=0.90
      expect(activeFused.score, greaterThanOrEqualTo(0.90));

      // In fallback mode: rule(0.60)*0.85 + ml(0.10)*(1.0-0.50) + policy(0.30)*0.50 = 0.51 + 0.05 + 0.15 = 0.71
      expect(fallbackFused.isFallback, isTrue);
      expect(fallbackFused.score, closeTo(0.71, 0.01));
      // Fallback score did not corrupt rule category or priority order
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
      expect(fusedFallbackOverride.score, closeTo(0.68, 0.02));
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

      final ruleMatch = MatchedRuleResult(
        ruleId: 'custom_rule',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'signal',
      );

      final fallbackModel = AnalysisResult(
        category: 'finance',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleMatch,
        modelResult: fallbackModel,
      );

      // rule(0.70)*0.85 + ml(0.05)*0.50 + policy(0.25)*0.50 = 0.595 + 0.025 + 0.125 = 0.745
      expect(fused.score, closeTo(0.745, 0.01));
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
