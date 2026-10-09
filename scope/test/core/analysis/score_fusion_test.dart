import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion Tests', () {
    test('critical bypass rule returns max confidence bypass result', () {
      const rule = MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Matched keyword "otp"',
        isSystemRule: true,
      );

      const modelResult = AnalysisResult(
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
      const rule = MatchedRuleResult(
        ruleId: 'custom_rule_1',
        category: 'msg',
        priority: 'medium',
        matchedSignal: 'Matched message rule',
        isSystemRule: false,
      );

      const modelResult = AnalysisResult(
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
      const rule = MatchedRuleResult(
        ruleId: 'custom_rule_2',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'Matched finance keyword',
        isSystemRule: false,
      );

      const fallbackModelResult = AnalysisResult(
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
      const fallbackModelResult = AnalysisResult(
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

  group('ScoreFusion Tests with Priority Capping & Tiering', () {
    const modelResult = AnalysisResult(
      category: 'promo',
      score: 0.60,
      engineName: 'ml_classifier',
      matchedSignals: ['ml_prediction'],
      latencyMs: 5,
    );

    test('system critical rule triggers deterministic score bypass (1.0)', () {
      const systemRuleMatch = MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'otp',
        priority: 'critical',
        matchedSignal: 'Content matches "verification code"',
        isSystemRule: true,
      );

      final result = ScoreFusion.fuse(
        ruleResult: systemRuleMatch,
        modelResult: modelResult,
      );

      expect(result.score, equals(1.0));
      expect(result.engineName, contains('rule bypass: otp_security'));
      expect(result.category, equals('otp'));
    });

    test('custom rule with high priority does NOT trigger critical bypass (score < 1.0)', () {
      const customRuleMatch = MatchedRuleResult(
        ruleId: 'rlhf-custom-1',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'Content matches "transfer"',
        isSystemRule: false,
      );

      final result = ScoreFusion.fuse(
        ruleResult: customRuleMatch,
        modelResult: modelResult,
      );

      expect(result.score, lessThan(1.0));
      expect(result.engineName, equals('score_fusion (hybrid)'));
      expect(result.category, equals('finance'));
    });

    test('custom rule claiming critical priority fails bypass check when isSystemRule is false', () {
      const spoofedCustomRuleMatch = MatchedRuleResult(
        ruleId: 'rlhf-spoofed-critical',
        category: 'finance',
        priority: 'critical',
        matchedSignal: 'Content matches "spoof"',
        isSystemRule: false,
      );

      final result = ScoreFusion.fuse(
        ruleResult: spoofedCustomRuleMatch,
        modelResult: modelResult,
      );

      expect(result.score, lessThan(1.0));
      expect(result.engineName, equals('score_fusion (hybrid)'));
    });
  });
}
