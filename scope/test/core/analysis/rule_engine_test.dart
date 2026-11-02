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
      TestWidgetsFlutterBinding.ensureInitialized();
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

    test('addReinforcementRule accepts valid custom rule and marks isCustom true', () {
      final validRule = NotificationRule(
        id: 'rlhf-custom-filter',
        category: 'social',
        priority: 'low',
        conditions: const RuleCondition(
          keywords: ['newsletter'],
        ),
      );

      engine.addReinforcementRule(validRule);
      expect(engine.customRules.length, equals(1));
      expect(engine.customRules.first.id, equals('rlhf-custom-filter'));
      expect(engine.customRules.first.isCustom, isTrue);
    });

    test('addReinforcementRule rejects privilege escalation attempt with critical priority', () {
      final invalidRule = NotificationRule(
        id: 'rlhf-escalate',
        category: 'sys',
        priority: 'critical',
        conditions: const RuleCondition(
          keywords: ['bypass'],
        ),
      );

      engine.addReinforcementRule(invalidRule);
      expect(engine.customRules, isEmpty);
    });

    test('addReinforcementRule rejects reserved system rule ID', () {
      final invalidRule = NotificationRule(
        id: 'otp_security',
        category: 'sys',
        priority: 'high',
        conditions: const RuleCondition(
          keywords: ['override'],
        ),
      );

      engine.addReinforcementRule(invalidRule);
      expect(engine.customRules, isEmpty);
    });

    test('system rules retain precedence over custom rules', () {
      final customOverridingRule = NotificationRule(
        id: 'rlhf-override-attempt',
        category: 'social',
        priority: 'low',
        conditions: const RuleCondition(
          keywords: ['debited'],
          titleKeywords: ['Alert'],
        ),
      );

      engine.addReinforcementRule(customOverridingRule);

      final notif = AppNotification(
        id: '1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content: 'Your account has been debited Rs. 15,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final match = engine.match(notif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('bank_debit'));
      expect(match.isCustom, isFalse);
    });
  });
}
