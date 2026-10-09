import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/rule_schema.dart';

void main() {
  group('CustomRuleSchema Validation Tests', () {
    test('rejects rule with missing/empty id', () {
      final jsonMap = {
        'id': '  ',
        'category': 'promotions',
        'priority': 'high',
        'conditions': {
          'keywords': ['discount']
        }
      };

      final result = CustomRuleSchema.validate(jsonMap);
      expect(result.isValid, isFalse);
      expect(result.error, contains('Rule ID must not be empty'));
    });

    test('rejects rule with empty conditions', () {
      final jsonMap = {
        'id': 'rlhf-1',
        'category': 'promotions',
        'priority': 'high',
        'conditions': {
          'packages': <String>[],
          'keywords': <String>[],
          'title_keywords': <String>[],
        }
      };

      final result = CustomRuleSchema.validate(jsonMap);
      expect(result.isValid, isFalse);
      expect(result.error, contains('must contain at least one non-empty condition'));
    });

    test('rejects keywords exceeding 50 characters', () {
      final longKeyword = 'a' * 51;
      final jsonMap = {
        'id': 'rlhf-2',
        'category': 'finance',
        'priority': 'high',
        'conditions': {
          'keywords': [longKeyword]
        }
      };

      final result = CustomRuleSchema.validate(jsonMap);
      expect(result.isValid, isFalse);
      expect(result.error, contains('exceeds maximum length of 50 characters'));
    });

    test('rejects rules exceeding maximum keyword limit of 20', () {
      final manyKeywords = List.generate(21, (index) => 'word$index');
      final jsonMap = {
        'id': 'rlhf-3',
        'category': 'social',
        'priority': 'medium',
        'conditions': {
          'keywords': manyKeywords
        }
      };

      final result = CustomRuleSchema.validate(jsonMap);
      expect(result.isValid, isFalse);
      expect(result.error, contains('exceeds maximum keyword limit of 20'));
    });

    test('automatically downgrades custom rule priority from critical to high', () {
      final jsonMap = {
        'id': 'rlhf-4',
        'category': 'finance',
        'priority': 'critical',
        'conditions': {
          'keywords': ['urgent_transfer']
        }
      };

      final result = CustomRuleSchema.validate(jsonMap);
      expect(result.isValid, isTrue);
      expect(result.rule, isNotNull);
      expect(result.rule!.priority, equals('high'));
      expect(result.rule!.isSystemRule, isFalse);
    });

    test('sanitizes control characters and whitespace from keywords', () {
      final jsonMap = {
        'id': 'rlhf-5',
        'category': 'work',
        'priority': 'high',
        'conditions': {
          'keywords': ['  \x00meeting\x1F  ']
        }
      };

      final result = CustomRuleSchema.validate(jsonMap);
      expect(result.isValid, isTrue);
      expect(result.rule!.conditions.keywords.first, equals('meeting'));
    });

    test('validates NotificationRule object directly', () {
      final rule = NotificationRule(
        id: 'rlhf-6',
        category: 'personal',
        priority: 'critical',
        conditions: const RuleCondition(
          keywords: ['birthday'],
        ),
      );

      final result = CustomRuleSchema.validate(rule);
      expect(result.isValid, isTrue);
      expect(result.rule!.priority, equals('high'));
      expect(result.rule!.isSystemRule, isFalse);
    });
  });
}
