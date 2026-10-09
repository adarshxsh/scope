import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/schema_validator.dart';

void main() {
  group('SchemaValidator Tests', () {
    test('accepts valid custom RLHF rule payload', () {
      final validRule = {
        'id': 'rlhf-12345',
        'category': 'promo',
        'priority': 'low',
        'conditions': {
          'keywords': ['sale', 'discount'],
          'packages': ['com.shopping.app'],
        },
      };

      final result = SchemaValidator.validateCustomRule(validRule);
      expect(result.isValid, isTrue);
      expect(result.error, isNull);
    });

    test('rejects rule payloads with "critical" priority', () {
      final criticalRule = {
        'id': 'rlhf-critical-attempt',
        'category': 'finance',
        'priority': 'critical',
        'conditions': {
          'keywords': ['bank', 'alert'],
        },
      };

      final result = SchemaValidator.validateCustomRule(criticalRule);
      expect(result.isValid, isFalse);
      expect(result.error, contains('prohibited from setting "critical" priority'));
    });

    test('rejects rule payloads claiming reserved system rule IDs', () {
      final reservedIds = [
        'otp_security',
        'finance_debit',
        'scholarship_portal',
        'family_urgent',
        'work_collaboration',
        'medical_reminder',
        'promo_deals',
        'social_engagement',
      ];

      for (final id in reservedIds) {
        final payload = {
          'id': id,
          'category': 'sys',
          'priority': 'high',
          'conditions': {
            'keywords': ['test'],
          },
        };

        final result = SchemaValidator.validateCustomRule(payload);
        expect(result.isValid, isFalse);
        expect(result.error, contains('reserved system rule ID'));
      }
    });

    test('rejects custom rule IDs that do not start with "rlhf-"', () {
      final payload = {
        'id': 'custom-rule-1',
        'category': 'msg',
        'priority': 'high',
        'conditions': {
          'keywords': ['hello'],
        },
      };

      final result = SchemaValidator.validateCustomRule(payload);
      expect(result.isValid, isFalse);
      expect(result.error, contains('must start with "rlhf-" prefix'));
    });

    test('rejects malformed field types (integer priority, non-map conditions, non-string lists)', () {
      // Priority as integer
      final badPriority = {
        'id': 'rlhf-1',
        'category': 'promo',
        'priority': 100,
        'conditions': {'keywords': ['test']},
      };
      expect(SchemaValidator.validateCustomRule(badPriority).isValid, isFalse);

      // Conditions as string
      final badConditions = {
        'id': 'rlhf-2',
        'category': 'promo',
        'priority': 'low',
        'conditions': 'keywords: test',
      };
      expect(SchemaValidator.validateCustomRule(badConditions).isValid, isFalse);

      // Keywords list contains integer
      final badKeywordItem = {
        'id': 'rlhf-3',
        'category': 'promo',
        'priority': 'low',
        'conditions': {
          'keywords': ['test', 123],
        },
      };
      expect(SchemaValidator.validateCustomRule(badKeywordItem).isValid, isFalse);
    });

    test('rejects non-permitted categories and priorities', () {
      final badCategory = {
        'id': 'rlhf-cat',
        'category': 'unknown_category',
        'priority': 'low',
        'conditions': {'keywords': ['test']},
      };
      expect(SchemaValidator.validateCustomRule(badCategory).isValid, isFalse);

      final badPriority = {
        'id': 'rlhf-prio',
        'category': 'promo',
        'priority': 'ultra_high',
        'conditions': {'keywords': ['test']},
      };
      expect(SchemaValidator.validateCustomRule(badPriority).isValid, isFalse);
    });

    test('rejects payloads with empty condition fields', () {
      final emptyConditions = {
        'id': 'rlhf-empty',
        'category': 'promo',
        'priority': 'low',
        'conditions': {
          'keywords': [],
          'packages': [],
        },
      };

      final result = SchemaValidator.validateCustomRule(emptyConditions);
      expect(result.isValid, isFalse);
      expect(result.error, contains('must contain at least one non-empty package, keyword, or title keyword'));
    });

    test('rejects string fields that exceed max length constraints', () {
      final longId = {
        'id': 'rlhf-${'a' * 100}',
        'category': 'promo',
        'priority': 'low',
        'conditions': {'keywords': ['test']},
      };
      expect(SchemaValidator.validateCustomRule(longId).isValid, isFalse);

      final longKeyword = {
        'id': 'rlhf-kw',
        'category': 'promo',
        'priority': 'low',
        'conditions': {
          'keywords': ['x' * 200],
        },
      };
      expect(SchemaValidator.validateCustomRule(longKeyword).isValid, isFalse);
    });
  });
}
