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

    test('Tier 1 base system rules evaluate before Tier 2 custom rules', () {
      // Add custom rule targeting HDFC debit notifications with priority 'medium'
      engine.addReinforcementRule(
        const NotificationRule(
          id: 'rlhf-override-hdfc',
          category: 'promo',
          priority: 'medium',
          conditions: RuleCondition(
            titleKeywords: ['Alert'],
            keywords: ['debited'],
          ),
        ),
      );

      final notif = AppNotification(
        id: '1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content: 'Your account has been debited Rs. 15,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Base rule (bank_debit in Tier 1) must evaluate first
      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('bank_debit'));
      expect(result.isCustom, isFalse);
      expect(result.isSystemRule, isTrue);
      expect(result.priority, equals('critical'));
    });

    test('addReinforcementRule clamps critical priority to high for custom rules', () {
      engine.addReinforcementRule(
        const NotificationRule(
          id: 'rlhf-malicious-critical',
          category: 'promo',
          priority: 'critical',
          conditions: RuleCondition(
            keywords: ['special offer'],
          ),
        ),
      );

      expect(engine.customRules.length, equals(1));
      expect(engine.customRules.first.priority, equals('high'));
      expect(engine.customRules.first.isCustom, isTrue);
    });

    test('addReinforcementRule rejects custom rules with empty conditions', () {
      engine.addReinforcementRule(
        const NotificationRule(
          id: 'rlhf-empty-conditions',
          category: 'promo',
          priority: 'high',
          conditions: RuleCondition(
            packages: [],
            keywords: [],
            titleKeywords: [],
          ),
        ),
      );

      expect(engine.customRules, isEmpty);
    });

    test('addReinforcementRule rejects custom rules using reserved system rule IDs', () {
      engine.addReinforcementRule(
        const NotificationRule(
          id: 'otp_security',
          category: 'promo',
          priority: 'high',
          conditions: RuleCondition(
            keywords: ['one-time passcode'],
          ),
        ),
      );

      expect(engine.customRules, isEmpty);
    });

    test('loadCustomRules resets state when reading malformed JSON format', () async {
      final file = File('./rlhf_rules.json');
      await file.writeAsString('{ invalid_json_content }');

      await engine.loadCustomRules();

      expect(engine.customRules, isEmpty);
      expect(await file.readAsString(), equals('[]'));

      if (await file.exists()) {
        await file.delete();
      }
    });
  });
}
