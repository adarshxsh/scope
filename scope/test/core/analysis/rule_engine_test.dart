import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
  });

  tearDownAll(() async {
    final file = File('./rlhf_rules.json');
    if (await file.exists()) {
      await file.delete();
    }
  });

  group('RuleEngine', () {
    const String sampleJson = '''
    {
      "version": "1.2.3",
      "rules": [
        {
          "id": "bank_debit",
          "category": "finance",
          "priority": "critical",
          "conditions": {
            "title_keywords": ["Alert", "HDFC"],
            "keywords": ["debited", "spent"]
          }
        },
        {
          "id": "whatsapp_mom",
          "category": "msg",
          "priority": "high",
          "conditions": {
            "packages": ["com.whatsapp"],
            "title_keywords": ["Mom"]
          }
        },
        {
          "id": "swiggy_promo",
          "category": "promo",
          "priority": "low",
          "conditions": {
            "keywords": ["50% off", "discount"]
          }
        }
      ]
    }
    ''';

    late RuleEngine engine;

    setUp(() {
      engine = RuleEngine();
      engine.compile(sampleJson);
    });

    test('compiles JSON rules and parses metadata correctly', () {
      expect(engine.version, equals('1.2.3'));
    });

    test('matches a debit transaction rule successfully (AND condition title+content)', () {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content: 'Your account has been debited Rs. 15,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('bank_debit'));
      expect(result.category, equals('finance'));
      expect(result.priority, equals('critical'));
      expect(result.matchedSignal, contains('Title matches "Alert"'));
      expect(result.matchedSignal, contains('Content matches "debited"'));
    });

    test('does not match debit rule if title condition is missing', () {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.random.app',
        title: 'Random notification',
        content: 'Your account was debited.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNull);
    });

    test('matches package and title keyword condition', () {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Call me back.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('whatsapp_mom'));
      expect(result.category, equals('msg'));
      expect(result.priority, equals('high'));
    });

    test('does not match package rule if package is different', () {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.instagram.android',
        title: 'Mom',
        content: 'Liked your photo',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNull);
    });

    test('matches low-priority promotional keywords', () {
      final notif = AppNotification(
        id: '3',
        packageName: 'com.swiggy',
        title: 'Delicious deals',
        content: 'Get 50% off on your first order!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('swiggy_promo'));
      expect(result.category, equals('promo'));
      expect(result.priority, equals('low'));
    });

    group('Schema Validation & Custom Rules', () {
      test('validates valid custom rule structure', () {
        final validMap = {
          'id': 'rlhf-101',
          'category': 'msg',
          'priority': 'high',
          'conditions': {
            'keywords': ['hello', 'world']
          }
        };
        final validation = RuleSchemaValidator.validateCustomRule(validMap);
        expect(validation.isValid, isTrue);
        expect(validation.error, isNull);
      });

      test('rejects custom rules with missing required properties', () {
        final missingId = {
          'category': 'msg',
          'priority': 'high',
          'conditions': {'keywords': ['test']}
        };
        expect(RuleSchemaValidator.validateCustomRule(missingId).isValid, isFalse);

        final missingCategory = {
          'id': 'rlhf-102',
          'priority': 'high',
          'conditions': {'keywords': ['test']}
        };
        expect(RuleSchemaValidator.validateCustomRule(missingCategory).isValid, isFalse);

        final missingConditions = {
          'id': 'rlhf-103',
          'category': 'msg',
          'priority': 'high',
        };
        expect(RuleSchemaValidator.validateCustomRule(missingConditions).isValid, isFalse);
      });

      test('rejects custom rules using reserved system rule IDs', () {
        final reserved = {
          'id': 'otp_security',
          'category': 'sys',
          'priority': 'high',
          'conditions': {'keywords': ['otp']}
        };
        final res = RuleSchemaValidator.validateCustomRule(reserved);
        expect(res.isValid, isFalse);
        expect(res.error, contains('reserved for system security rules'));
      });

      test('rejects custom rules with empty condition blocks (Requirement 5)', () {
        final emptyConditions = {
          'id': 'rlhf-104',
          'category': 'msg',
          'priority': 'high',
          'conditions': {
            'packages': [],
            'keywords': ['   '],
            'title_keywords': []
          }
        };
        final res = RuleSchemaValidator.validateCustomRule(emptyConditions);
        expect(res.isValid, isFalse);
        expect(res.error, contains('non-empty condition block'));
      });

      test('rejects custom rules with invalid condition data types', () {
        final invalidTypes = {
          'id': 'rlhf-105',
          'category': 'msg',
          'priority': 'high',
          'conditions': {
            'keywords': [123, 456]
          }
        };
        expect(RuleSchemaValidator.validateCustomRule(invalidTypes).isValid, isFalse);
      });
    });

    group('Priority Caps & Evaluation Order', () {
      test('automatically demotes custom rules from critical to high priority (Requirement 2)', () {
        final customCriticalMap = {
          'id': 'rlhf-bypass-attempt',
          'category': 'promo',
          'priority': 'critical',
          'conditions': {
            'keywords': ['free money']
          }
        };

        final rule = NotificationRule.fromMap(customCriticalMap, isCustom: true);
        expect(rule.priority, equals('high'));
      });

      test('addReinforcementRule demotes critical priority custom rule', () {
        final customRule = NotificationRule(
          id: 'rlhf-999',
          category: 'promo',
          priority: 'critical',
          conditions: const RuleCondition(keywords: ['win prize']),
        );

        engine.addReinforcementRule(customRule);

        final notif = AppNotification(
          id: '99',
          packageName: 'com.spam.app',
          title: 'Special Offer',
          content: 'You win prize today!',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final match = engine.match(notif);
        expect(match, isNotNull);
        expect(match!.ruleId, equals('rlhf-999'));
        expect(match.priority, equals('high'));
      });

      test('base system security rules take precedence over custom user rules (Requirement 3)', () {
        final conflictingCustomRule = NotificationRule(
          id: 'rlhf-custom-hdfc',
          category: 'promo',
          priority: 'low',
          conditions: const RuleCondition(
            packages: ['com.hdfc.mobilebanking'],
            keywords: ['debited'],
          ),
        );

        engine.addReinforcementRule(conflictingCustomRule);

        final notif = AppNotification(
          id: '1',
          packageName: 'com.hdfc.mobilebanking',
          title: 'HDFC Bank Alert',
          content: 'Your account has been debited Rs. 15,000.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = engine.match(notif);
        expect(result, isNotNull);
        expect(result!.ruleId, equals('bank_debit'));
        expect(result.priority, equals('critical'));
      });
    });

    group('Regex Condition Sanitization', () {
      test('sanitizes regex wildcards and handles invalid regex syntax gracefully (Requirement 4)', () {
        final wildcardRule = NotificationRule(
          id: 'rlhf-wildcard',
          category: 'msg',
          priority: 'medium',
          conditions: const RuleCondition(
            keywords: ['.*', '[open-bracket', '(?invalid-regex'],
          ),
        );

        engine.addReinforcementRule(wildcardRule);

        final normalNotif = AppNotification(
          id: '50',
          packageName: 'com.chat',
          title: 'Message',
          content: 'Just saying hello!',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final normalResult = engine.match(normalNotif);
        expect(normalResult, isNull);

        final literalNotif = AppNotification(
          id: '51',
          packageName: 'com.chat',
          title: 'Message',
          content: 'Matched .* literal',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final literalResult = engine.match(literalNotif);
        expect(literalResult, isNotNull);
        expect(literalResult!.ruleId, equals('rlhf-wildcard'));
      });
    });
  });
}
