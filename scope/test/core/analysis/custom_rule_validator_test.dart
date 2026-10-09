import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/custom_rule_validator.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('CustomRuleValidator Unit Tests', () {
    test('downgrades priority "critical" to "high"', () {
      const rule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'msg',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['urgent'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitize(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.priority, equals('high'));
      expect(sanitized.id, equals('rlhf-custom-1'));
    });

    test('accepts valid priorities (high, medium, low)', () {
      for (final priority in ['high', 'medium', 'low', 'HIGH', 'Medium', 'LOW']) {
        final rule = NotificationRule(
          id: 'rlhf-custom-valid-$priority',
          category: 'promo',
          priority: priority,
          conditions: const RuleCondition(
            keywords: ['deal'],
          ),
        );

        final sanitized = CustomRuleValidator.validateAndSanitize(rule);
        expect(sanitized, isNotNull);
        expect(sanitized!.priority, equals(priority.toLowerCase()));
      }
    });

    test('rejects rules with invalid priority strings', () {
      const rule = NotificationRule(
        id: 'rlhf-invalid-prio',
        category: 'promo',
        priority: 'super_high',
        conditions: RuleCondition(
          keywords: ['deal'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitize(rule);
      expect(sanitized, isNull);
    });

    test('rejects custom rules impersonating reserved system rule IDs', () {
      for (final reservedId in ['otp_security', 'finance_debit', 'scholarship_portal', 'bank_debit']) {
        final rule = NotificationRule(
          id: reservedId,
          category: 'finance',
          priority: 'high',
          conditions: const RuleCondition(
            keywords: ['passcode'],
          ),
        );

        final sanitized = CustomRuleValidator.validateAndSanitize(rule);
        expect(sanitized, isNull);
      }
    });

    test('rejects custom rules impersonating active system rule IDs', () {
      final activeSystemIds = {'active_system_rule_1', 'system_promo'};

      final rule = NotificationRule(
        id: 'active_system_rule_1',
        category: 'finance',
        priority: 'high',
        conditions: const RuleCondition(
          keywords: ['bank'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitize(
        rule,
        systemRuleIds: activeSystemIds,
      );
      expect(sanitized, isNull);
    });

    test('rejects unconstrained rules with empty conditions', () {
      const rule = NotificationRule(
        id: 'rlhf-empty-conditions',
        category: 'general',
        priority: 'low',
        conditions: RuleCondition(
          packages: [],
          titleKeywords: [],
          keywords: [],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitize(rule);
      expect(sanitized, isNull);
    });

    test('rejects rules with empty or whitespace-only IDs', () {
      const rule = NotificationRule(
        id: '   ',
        category: 'general',
        priority: 'low',
        conditions: RuleCondition(
          keywords: ['test'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitize(rule);
      expect(sanitized, isNull);
    });

    test('validateAndSanitizeMap gracefully handles malformed maps', () {
      final malformedMap = <String, dynamic>{
        'invalid_key': 'no_id',
      };

      final result = CustomRuleValidator.validateAndSanitizeMap(malformedMap);
      expect(result, isNull);
    });
  });

  group('Two-Tier Rule Engine & Provenance Tests', () {
    const sampleSystemJson = '''
    {
      "version": "2.0.0",
      "rules": [
        {
          "id": "otp_security",
          "category": "msg",
          "priority": "critical",
          "conditions": {
            "keywords": ["verification code", "one time password"]
          }
        },
        {
          "id": "finance_debit",
          "category": "finance",
          "priority": "critical",
          "conditions": {
            "keywords": ["debited", "account alert"]
          }
        }
      ]
    }
    ''';

    late RuleEngine engine;

    setUp(() {
      engine = RuleEngine();
      engine.compile(sampleSystemJson);
    });

    test('system rules execute before custom user rules', () {
      // Add a custom user rule targeting 'verification code' as 'low' priority
      const customRule = NotificationRule(
        id: 'rlhf-custom-otp-override',
        category: 'social',
        priority: 'low',
        conditions: RuleCondition(
          keywords: ['verification code'],
        ),
      );

      final added = engine.addReinforcementRule(customRule);
      expect(added, isTrue);

      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your verification code is 492012.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      // System rule MUST win over custom rule
      expect(result!.ruleId, equals('otp_security'));
      expect(result.priority, equals('critical'));
      expect(result.isSystemRule, isTrue);
    });

    test('custom user rules execute if no system rule matches', () {
      const customRule = NotificationRule(
        id: 'rlhf-mom-rule',
        category: 'msg',
        priority: 'high',
        conditions: RuleCondition(
          packages: ['com.whatsapp'],
          titleKeywords: ['Mom'],
        ),
      );

      final added = engine.addReinforcementRule(customRule);
      expect(added, isTrue);

      final notif = AppNotification(
        id: 'n2',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Please call me when you land.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('rlhf-mom-rule'));
      expect(result.priority, equals('high'));
      expect(result.isSystemRule, isFalse);
    });

    test('custom rule with critical priority is downgraded and flagged as non-system', () {
      const maliciousCustomRule = NotificationRule(
        id: 'rlhf-attempt-critical',
        category: 'finance',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['custom_keyword'],
        ),
      );

      final added = engine.addReinforcementRule(maliciousCustomRule);
      expect(added, isTrue);

      final customRuleInEngine = engine.customRules.firstWhere((r) => r.id == 'rlhf-attempt-critical');
      expect(customRuleInEngine.priority, equals('high'));

      final notif = AppNotification(
        id: 'n3',
        packageName: 'com.custom.app',
        title: 'Test',
        content: 'Has custom_keyword here',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final matchResult = engine.match(notif);
      expect(matchResult, isNotNull);
      expect(matchResult!.isSystemRule, isFalse);
      expect(matchResult.priority, equals('high'));
    });

    test('score fusion verifies rule provenance before triggering critical bypass', () {
      final systemMatch = const MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'msg',
        priority: 'critical',
        matchedSignal: 'Content matches "verification code"',
        isSystemRule: true,
      );

      final customMatch = const MatchedRuleResult(
        ruleId: 'rlhf-fake-otp',
        category: 'msg',
        priority: 'critical', // Even if custom rule priority was somehow 'critical'
        matchedSignal: 'Content matches "code"',
        isSystemRule: false,
      );

      final modelResult = const AnalysisResult(
        category: 'msg',
        score: 0.3,
        engineName: 'ml_model',
        matchedSignals: [],
        latencyMs: 1,
      );

      // System rule triggers critical bypass (score = 1.0)
      final systemFused = ScoreFusion.fuse(ruleResult: systemMatch, modelResult: modelResult);
      expect(systemFused.score, equals(1.0));
      expect(systemFused.engineName, contains('rule bypass'));

      // Custom rule DOES NOT trigger critical bypass
      final customFused = ScoreFusion.fuse(ruleResult: customMatch, modelResult: modelResult);
      expect(customFused.score, lessThan(1.0));
      expect(customFused.engineName, equals('score_fusion (hybrid)'));
    });

    test('custom rules capacity is capped at 50', () {
      final engineCap = RuleEngine();
      engineCap.compile(sampleSystemJson);

      for (int i = 0; i < 60; i++) {
        engineCap.addReinforcementRule(
          NotificationRule(
            id: 'rlhf-rule-$i',
            category: 'promo',
            priority: 'low',
            conditions: RuleCondition(
              keywords: ['keyword_$i'],
            ),
          ),
        );
      }

      expect(engineCap.customRules.length, equals(50));
      // Latest rule should be at the top
      expect(engineCap.customRules.first.id, equals('rlhf-rule-59'));
    });
  });
}
