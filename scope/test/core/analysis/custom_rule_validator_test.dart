import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/custom_rule_validator.dart';
import 'package:scope/core/analysis/rule_engine.dart';

void main() {
  group('CustomRuleValidator Tests', () {
    test('valid custom rule passes validation and retains non-critical priority', () {
      const rule = NotificationRule(
        id: 'rlhf-test-1',
        category: 'social',
        priority: 'medium',
        conditions: RuleCondition(
          keywords: ['friend', 'invite'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.id, equals('rlhf-test-1'));
      expect(sanitized.priority, equals('medium'));
      expect(sanitized.isCustom, isTrue);
      expect(sanitized.conditions.keywords, equals(['friend', 'invite']));
    });

    test('automatically prepends rlhf- prefix if custom ID lacks prefix', () {
      const rule = NotificationRule(
        id: 'user_keyword_rule',
        category: 'work',
        priority: 'high',
        conditions: RuleCondition(
          keywords: ['project'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.id, equals('rlhf-user_keyword_rule'));
      expect(sanitized.isCustom, isTrue);
    });

    test('preserves custom- prefix if present', () {
      const rule = NotificationRule(
        id: 'custom-vip-alert',
        category: 'msg',
        priority: 'high',
        conditions: RuleCondition(
          titleKeywords: ['boss'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.id, equals('custom-vip-alert'));
    });

    test('rejects custom rules that attempt to spoof reserved system rule IDs', () {
      const reservedIds = [
        'otp_security',
        'finance_debit',
        'scholarship_portal',
        'family_urgent',
        'work_collaboration',
        'medical_reminder',
        'promo_deals',
        'social_engagement',
      ];

      for (final reservedId in reservedIds) {
        final rule = NotificationRule(
          id: reservedId,
          category: 'finance',
          priority: 'critical',
          conditions: const RuleCondition(keywords: ['debited']),
        );

        final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
        expect(sanitized, isNull, reason: 'Reserved ID $reservedId should be rejected');
      }
    });

    test('automatically downgrades critical priority to high for custom rules', () {
      const rule = NotificationRule(
        id: 'rlhf-critical-attempt',
        category: 'financial',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['transfer'],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.priority, equals('high'));
    });

    test('discards rules with empty condition strings or empty condition arrays', () {
      const emptyArrayRule = NotificationRule(
        id: 'rlhf-empty-1',
        category: 'promo',
        priority: 'low',
        conditions: RuleCondition(),
      );

      expect(CustomRuleValidator.validateAndSanitizeRule(emptyArrayRule), isNull);

      const whitespaceRule = NotificationRule(
        id: 'rlhf-empty-2',
        category: 'promo',
        priority: 'low',
        conditions: RuleCondition(
          keywords: ['', '   '],
          titleKeywords: ['  '],
        ),
      );

      expect(CustomRuleValidator.validateAndSanitizeRule(whitespaceRule), isNull);
    });

    test('removes empty string items and truncates long strings in conditions', () {
      final longString = 'a' * 100;
      final rule = NotificationRule(
        id: 'rlhf-long-string',
        category: 'promo',
        priority: 'low',
        conditions: RuleCondition(
          keywords: ['  valid  ', '', longString],
        ),
      );

      final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.conditions.keywords.length, equals(2));
      expect(sanitized.conditions.keywords[0], equals('valid'));
      expect(sanitized.conditions.keywords[1].length, equals(64));
    });

    test('validateCustomRuleList filters malformed entries and caps list at 50 rules', () {
      final rawList = <Map<String, dynamic>>[];

      // Add reserved system rule entry (should be discarded)
      rawList.add({
        'id': 'otp_security',
        'category': 'sys',
        'priority': 'critical',
        'conditions': {'keywords': ['otp']}
      });

      // Add malformed entry with empty condition (should be discarded)
      rawList.add({
        'id': 'rlhf-malformed',
        'category': 'promo',
        'priority': 'low',
        'conditions': {'keywords': ['']}
      });

      // Add 60 valid custom rules
      for (int i = 0; i < 60; i++) {
        rawList.add({
          'id': 'rlhf-rule-$i',
          'category': 'msg',
          'priority': 'medium',
          'conditions': {
            'keywords': ['keyword-$i']
          }
        });
      }

      final validatedList = CustomRuleValidator.validateCustomRuleList(rawList);
      expect(validatedList.length, equals(50));
      expect(validatedList.any((r) => r.id == 'otp_security'), isFalse);
      expect(validatedList.any((r) => r.id == 'rlhf-malformed'), isFalse);
      expect(validatedList.every((r) => r.isCustom), isTrue);
    });
  });
}
