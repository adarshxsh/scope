import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
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

    group('Dual-Chain Evaluation & System Rule Precedence', () {
      test('system rules always evaluate before custom rules', () {
        // Add custom rule that attempts to override bank debit notifications
        final customRule = NotificationRule(
          id: 'rlhf-override-bank',
          category: 'promo',
          priority: 'low',
          conditions: const RuleCondition(
            keywords: ['debited'],
          ),
        );
        final added = engine.addReinforcementRule(customRule);
        expect(added, isTrue);

        final notif = AppNotification(
          id: '1',
          packageName: 'com.hdfc.mobilebanking',
          title: 'HDFC Bank Alert',
          content: 'Your account has been debited Rs. 15,000.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = engine.match(notif);
        expect(result, isNotNull);
        expect(result!.ruleId, equals('bank_debit')); // System rule wins
        expect(result.isSystemRule, isTrue);
      });

      test('custom rule matches when no system rule matches', () {
        final customRule = NotificationRule(
          id: 'rlhf-custom-messaging',
          category: 'msg',
          priority: 'medium',
          conditions: const RuleCondition(
            packages: ['com.telegram.messenger'],
            keywords: ['project'],
          ),
        );
        engine.addReinforcementRule(customRule);

        final notif = AppNotification(
          id: '2',
          packageName: 'com.telegram.messenger',
          title: 'Team Chat',
          content: 'Update on the project status.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = engine.match(notif);
        expect(result, isNotNull);
        expect(result!.ruleId, equals('rlhf-custom-messaging'));
        expect(result.isSystemRule, isFalse);
      });
    });

    group('Custom Rule Schema Validation & Priority Ceilings', () {
      test('rejects custom rules missing rlhf- prefix in id', () {
        final invalidRule = NotificationRule(
          id: 'invalid_custom_id',
          category: 'msg',
          priority: 'high',
          conditions: const RuleCondition(keywords: ['hello']),
        );
        final added = engine.addReinforcementRule(invalidRule);
        expect(added, isFalse);
        expect(engine.customRules, isEmpty);
      });

      test('demotes critical priority custom rules to high priority', () {
        final customRule = NotificationRule(
          id: 'rlhf-critical-attempt',
          category: 'msg',
          priority: 'critical',
          conditions: const RuleCondition(keywords: ['urgent']),
        );
        final added = engine.addReinforcementRule(customRule);
        expect(added, isTrue);

        final savedRule = engine.customRules.firstWhere((r) => r.id == 'rlhf-critical-attempt');
        expect(savedRule.priority, equals('high'));
      });

      test('rejects custom rules with empty condition strings or wildcard keywords', () {
        final emptyCondRule = NotificationRule(
          id: 'rlhf-empty-cond',
          category: 'promo',
          priority: 'medium',
          conditions: const RuleCondition(
            keywords: ['', ' ', '*'],
            titleKeywords: ['?'],
          ),
        );
        final added = engine.addReinforcementRule(emptyCondRule);
        expect(added, isFalse);
      });

      test('sanitizes valid keywords while removing empty or single-char strings', () {
        final rule = NotificationRule(
          id: 'rlhf-sanitized',
          category: 'work',
          priority: 'high',
          conditions: const RuleCondition(
            keywords: ['a', 'validKeyword', ' ', '*'],
          ),
        );
        final added = engine.addReinforcementRule(rule);
        expect(added, isTrue);

        final saved = engine.customRules.firstWhere((r) => r.id == 'rlhf-sanitized');
        expect(saved.conditions.keywords, equals(['validKeyword']));
      });
    });
  });
}
