import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion Tests', () {
    final defaultModelResult = const AnalysisResult(
      category: 'msg',
      score: 0.50,
      engineName: 'litert_model',
      matchedSignals: [],
      latencyMs: 1,
      isFallback: false,
    );

    test('system critical rule triggers score bypass (score = 1.0)', () {
      final systemRule = const MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Content matches "otp"',
        isCustom: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: systemRule,
        modelResult: defaultModelResult,
      );

      expect(fused.category, equals('sys'));
      expect(fused.score, equals(1.0));
      expect(fused.engineName, contains('rule bypass: otp_security'));
      expect(fused.isFallback, isFalse);
    });

    test('custom rule NEVER triggers critical score bypass, even if claiming critical priority or reserved ID', () {
      final customRulePrivilegeEscalationAttempt = const MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Content matches "otp"',
        isCustom: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRulePrivilegeEscalationAttempt,
        modelResult: defaultModelResult,
      );

      expect(fused.score, isNot(equals(1.0)));
      expect(fused.engineName, equals('score_fusion (hybrid)'));
      expect(fused.isFallback, isFalse);
    });

    test('authentic model result blends scores when rule matches', () {
      final rule = const MatchedRuleResult(
        ruleId: 'custom_rule_1',
        category: 'msg',
        priority: 'medium',
        matchedSignal: 'Matched message rule',
        isCustom: false,
      );

      final modelResult = const AnalysisResult(
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

    test('custom rule matches use standard hybrid confidence scoring', () {
      final customRule = const MatchedRuleResult(
        ruleId: 'rlhf-promo-filter',
        category: 'promo',
        priority: 'low',
        matchedSignal: 'Content matches "sale"',
        isCustom: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRule,
        modelResult: const AnalysisResult(
          category: 'promo',
          score: 0.80,
          engineName: 'litert_model',
          matchedSignals: [],
          latencyMs: 1,
          isFallback: false,
        ),
      );

      expect(fused.engineName, equals('score_fusion (hybrid)'));
      expect(fused.score, greaterThanOrEqualTo(0.85));
      expect(fused.score, lessThan(1.0));
      expect(fused.isFallback, isFalse);
    });

    test('fallback model result does NOT blend score into rule match result', () {
      final rule = const MatchedRuleResult(
        ruleId: 'custom_rule_2',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'Matched finance keyword',
        isCustom: false,
      );

      final fallbackModelResult = const AnalysisResult(
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
      final fallbackModelResult = const AnalysisResult(
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
}
