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

      expect(fused.score, equals(1.0));
      expect(fused.engineName, contains('rule bypass'));
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
        ),
      );

      expect(fused.engineName, equals('score_fusion (hybrid)'));
      expect(fused.score, greaterThanOrEqualTo(0.85));
      expect(fused.score, lessThan(1.0));
    });
  });
}
