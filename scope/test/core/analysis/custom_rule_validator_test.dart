import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/custom_rule_validator.dart';
import 'package:scope/core/analysis/rule_engine.dart';

void main() {
  group('CustomRuleValidator Tests', () {
    test('isValidRuleMap validates schema correctness', () {
      final validMap = {
        'id': 'rlhf-123',
        'category': 'msg',
        'priority': 'high',
        'conditions': {
          'keywords': ['work', 'project'],
          'title_keywords': ['meeting'],
          'packages': ['com.slack'],
        },
      };

      expect(CustomRuleValidator.isValidRuleMap(validMap), isTrue);
    });

    test('isValidRuleMap rejects missing required fields', () {
      final missingId = {
        'category': 'msg',
        'priority': 'high',
        'conditions': {
          'keywords': ['work'],
        },
      };

      expect(CustomRuleValidator.isValidRuleMap(missingId), isFalse);

      final missingConditions = {
        'id': 'rlhf-123',
        'category': 'msg',
        'priority': 'high',
      };

      expect(CustomRuleValidator.isValidRuleMap(missingConditions), isFalse);
    });

    test('isValidRuleMap rejects reserved system rule IDs', () {
      final reservedIdMap = {
        'id': 'otp_security',
        'category': 'sys',
        'priority': 'high',
        'conditions': {
          'keywords': ['code'],
        },
      };

      expect(CustomRuleValidator.isValidRuleMap(reservedIdMap), isFalse);
    });

    test('isValidRuleMap rejects keywords shorter than 3 characters', () {
      final shortKeywordMap = {
        'id': 'rlhf-123',
        'category': 'msg',
        'priority': 'high',
        'conditions': {
          'keywords': ['at', 'in'],
        },
      };

      expect(CustomRuleValidator.isValidRuleMap(shortKeywordMap), isFalse);
    });

    test('isValidRuleMap rejects oversized keyword lists (> 10)', () {
      final oversizedMap = {
        'id': 'rlhf-123',
        'category': 'msg',
        'priority': 'high',
        'conditions': {
          'keywords': List.generate(11, (i) => 'keyword_$i'),
        },
      };

      expect(CustomRuleValidator.isValidRuleMap(oversizedMap), isFalse);
    });

    test('clampAndSanitizeRule clamps critical priority to high', () {
      const rule = NotificationRule(
        id: 'rlhf-critical-test',
        category: 'msg',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['urgent', 'project'],
        ),
      );

      final sanitized = CustomRuleValidator.clampAndSanitizeRule(rule);
      expect(sanitized.priority, equals('high'));
      expect(sanitized.id, equals('rlhf-critical-test'));
    });

    test('clampAndSanitizeRule filters keywords shorter than 3 characters', () {
      const rule = NotificationRule(
        id: 'rlhf-short-kw',
        category: 'msg',
        priority: 'medium',
        conditions: RuleCondition(
          keywords: ['a', 'to', 'valid', 'code'],
        ),
      );

      final sanitized = CustomRuleValidator.clampAndSanitizeRule(rule);
      expect(sanitized.conditions.keywords, equals(['valid', 'code']));
    });

    test('validateAndSanitizeRules bounds total custom rules quota to 50', () {
      final rawList = List.generate(60, (i) => {
        'id': 'rlhf-$i',
        'category': 'msg',
        'priority': 'critical',
        'conditions': {
          'keywords': ['test_keyword_$i'],
        },
      });

      final validated = CustomRuleValidator.validateAndSanitizeRules(rawList);
      expect(validated.length, equals(50));
      for (final rule in validated) {
        expect(rule.priority, equals('high'));
      }
    });

    test('validateAndSanitizeRules handles corrupt payload elements safely', () {
      final rawList = [
        'invalid string element',
        12345,
        {
          'id': 'rlhf-valid',
          'category': 'msg',
          'priority': 'high',
          'conditions': {
            'keywords': ['valid'],
          },
        },
        {
          'id': 'rlhf-corrupt',
          // missing category
          'conditions': {},
        },
      ];

      final validated = CustomRuleValidator.validateAndSanitizeRules(rawList);
      expect(validated.length, equals(1));
      expect(validated.first.id, equals('rlhf-valid'));
    });
  });
}
