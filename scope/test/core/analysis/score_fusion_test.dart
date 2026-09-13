import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion Tests with Priority Capping & Tiering', () {
    final modelResult = const AnalysisResult(
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
