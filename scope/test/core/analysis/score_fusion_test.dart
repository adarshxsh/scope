import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion', () {
    final modelResult = const AnalysisResult(
      category: 'social',
      score: 0.6,
      engineName: 'litert',
      matchedSignals: [],
      latencyMs: 1,
    );

    test('grants deterministic bypass score 1.0 for base critical rules', () {
      final baseRuleMatch = const MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Content matches "otp"',
        isCustom: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: baseRuleMatch,
        modelResult: modelResult,
      );

      expect(fused.score, equals(1.0));
      expect(fused.category, equals('sys'));
      expect(fused.engineName, contains('rule bypass: otp_security'));
    });

    test('disallows custom rules from triggering deterministic score bypass', () {
      final customRuleMatch = const MatchedRuleResult(
        ruleId: 'rlhf-spoof',
        category: 'sys',
        priority: 'high',
        matchedSignal: 'Content matches "custom_signal"',
        isCustom: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: customRuleMatch,
        modelResult: modelResult,
      );

      expect(fused.score, isNot(equals(1.0)));
      expect(fused.engineName, equals('score_fusion (hybrid)'));
    });
  });
}
