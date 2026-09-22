import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall methodCall) async {
      return '.';
    },
  );

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

    test('Tier-1 system rules execute prior to Tier-2 custom rules and prevent shadowing', () {
      // Add a custom rule that matches HDFC Bank Alert with promo category
      final customRule = NotificationRule(
        id: 'rlhf-12345',
        category: 'promo',
        priority: 'low',
        conditions: const RuleCondition(
          titleKeywords: ['Alert', 'HDFC'],
          keywords: ['debited'],
        ),
      );

      engine.addReinforcementRule(customRule);

      final notif = AppNotification(
        id: '1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content: 'Your account has been debited Rs. 15,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('bank_debit')); // System rule matched first
      expect(result.isSystemRule, isTrue);
      expect(result.priority, equals('critical'));
    });

    test('Custom rules attempting to set priority: "critical" are automatically capped to "high"', () {
      final customRule = NotificationRule(
        id: 'rlhf-critical-attempt',
        category: 'msg',
        priority: 'critical',
        conditions: const RuleCondition(
          keywords: ['unauthorized-access-signal'],
        ),
      );

      engine.addReinforcementRule(customRule);

      final notif = AppNotification(
        id: '10',
        packageName: 'com.test.app',
        title: 'Security',
        content: 'unauthorized-access-signal detected',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('rlhf-critical-attempt'));
      expect(result.priority, equals('high')); // Capped from critical to high
      expect(result.isSystemRule, isFalse);
    });

    test('Custom rules attempting to use reserved IDs or missing rlhf- prefix are rejected', () {
      // Attempting reserved system ID 'otp_security'
      final reservedRule = NotificationRule(
        id: 'otp_security',
        category: 'sys',
        priority: 'high',
        conditions: const RuleCondition(
          keywords: ['fake_otp_signal'],
        ),
      );

      expect(
        () => engine.addReinforcementRule(reservedRule),
        throwsArgumentError,
      );
    });
  });
}
