import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/custom_rule_validator.dart';
import 'package:scope/core/analysis/rule_engine.dart';

void main() {
  group('CustomRuleValidator', () {
    test('rejects custom rules using reserved system IDs', () {
      const reservedIds = ['otp_security', 'finance_debit', 'scholarship_portal'];

      for (final id in reservedIds) {
        final rule = NotificationRule(
          id: id,
          category: 'security',
          priority: 'high',
          conditions: const RuleCondition(keywords: ['test']),
        );
        expect(CustomRuleValidator.validate(rule), isNull);
      }
    });

    test('rejects custom rules with empty or whitespace ID', () {
      final rule = NotificationRule(
        id: '   ',
        category: 'custom',
        priority: 'high',
        conditions: const RuleCondition(keywords: ['test']),
      );
      expect(CustomRuleValidator.validate(rule), isNull);
    });

    test('clamps critical priority to high', () {
      final rule = NotificationRule(
        id: 'rlhf-1',
        category: 'custom',
        priority: 'critical',
        conditions: const RuleCondition(keywords: ['important']),
      );

      final sanitized = CustomRuleValidator.validate(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.priority, equals('high'));
    });

    test('rejects conditions exceeding keyword capacity limits (> 10)', () {
      final oversizedKeywords = List.generate(11, (i) => 'word$i');
      final rule = NotificationRule(
        id: 'rlhf-2',
        category: 'custom',
        priority: 'high',
        conditions: RuleCondition(keywords: oversizedKeywords),
      );

      expect(CustomRuleValidator.validate(rule), isNull);
    });

    test('rejects keywords exceeding character length limit (> 64 chars)', () {
      final longKeyword = 'a' * 65;
      final rule = NotificationRule(
        id: 'rlhf-3',
        category: 'custom',
        priority: 'high',
        conditions: RuleCondition(keywords: [longKeyword]),
      );

      expect(CustomRuleValidator.validate(rule), isNull);
    });

    test('rejects empty or whitespace-only conditions', () {
      final rule = NotificationRule(
        id: 'rlhf-4',
        category: 'custom',
        priority: 'high',
        conditions: const RuleCondition(
          packages: ['   '],
          keywords: [''],
          titleKeywords: [],
        ),
      );

      expect(CustomRuleValidator.validate(rule), isNull);
    });

    test('sanitizes valid rule correctly', () {
      final rule = NotificationRule(
        id: 'rlhf-5',
        category: 'msg',
        priority: 'low',
        conditions: const RuleCondition(
          packages: ['com.example.app'],
          titleKeywords: ['urgent'],
          keywords: ['meeting'],
        ),
      );

      final sanitized = CustomRuleValidator.validate(rule);
      expect(sanitized, isNotNull);
      expect(sanitized!.id, equals('rlhf-5'));
      expect(sanitized.category, equals('msg'));
      expect(sanitized.priority, equals('low'));
      expect(sanitized.conditions.packages, equals(['com.example.app']));
      expect(sanitized.conditions.titleKeywords, equals(['urgent']));
      expect(sanitized.conditions.keywords, equals(['meeting']));
    });
  });
}
