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
      expect(fused.score, equals(0.90)); // (0.85 + 0.80)/2 = 0.825 clamped to 0.90
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

    test('custom rule is prohibited from triggering maximum-confidence security bypass', () {
      final customRule = MatchedRuleResult(
        ruleId: 'rlhf-spoofed-otp',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Custom keyword match',
        isCustom: true,
      );

      final modelResult = AnalysisResult(
        category: 'promo',
        score: 0.30,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores'],
        latencyMs: 5,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRule,
        modelResult: modelResult,
      );

      // Must NOT trigger 1.0 confidence bypass because it is a custom rule (isCustom: true)
      expect(fused.score, isNot(equals(1.0)));
      expect(fused.engineName, isNot(contains('rule bypass')));
      expect(fused.engineName, equals('score_fusion (hybrid)'));
    });
  });
}
