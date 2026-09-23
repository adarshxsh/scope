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

    test('addReinforcementRule sanitizes rule, demotes critical priority, and sets isCustom flag', () {
      const customRule = NotificationRule(
        id: 'user_custom_1',
        category: 'social',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['party'],
        ),
      );

      engine.addReinforcementRule(customRule);

      final notif = AppNotification(
        id: '10',
        packageName: 'com.example.chat',
        title: 'Event',
        content: 'Join the weekend party!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final matchResult = engine.match(notif);
      expect(matchResult, isNotNull);
      expect(matchResult!.ruleId, equals('rlhf-user_custom_1'));
      expect(matchResult.priority, equals('high')); // Demoted from critical to high
      expect(matchResult.isCustom, isTrue);
      expect(matchResult.isSystemRule, isFalse);
    });

    test('addReinforcementRule ignores rules with empty condition strings or reserved system rule IDs', () {
      const reservedRule = NotificationRule(
        id: 'otp_security',
        category: 'sys',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['spoof'],
        ),
      );

      engine.addReinforcementRule(reservedRule);

      final notif = AppNotification(
        id: '11',
        packageName: 'com.example.app',
        title: 'Security',
        content: 'This is a spoof message',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNull);
    });

    test('system rules take precedence over custom rules (Tier 1 vs Tier 2)', () {
      const conflictingCustomRule = NotificationRule(
        id: 'rlhf-debit-override',
        category: 'promo',
        priority: 'low',
        conditions: RuleCondition(
          titleKeywords: ['Alert'],
          keywords: ['debited'],
        ),
        isCustom: true,
      );

      engine.addReinforcementRule(conflictingCustomRule);

      final debitNotif = AppNotification(
        id: '12',
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content: 'Your account has been debited Rs. 15,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final matchResult = engine.match(debitNotif);
      expect(matchResult, isNotNull);
      expect(matchResult!.ruleId, equals('bank_debit')); // Tier 1 system rule wins
      expect(matchResult.isCustom, isFalse);
      expect(matchResult.isSystemRule, isTrue);
    });
  });
}
