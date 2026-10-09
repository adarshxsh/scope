import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_crypto.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuleEngine', () {
    final Map<String, dynamic> samplePayload = {
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
    };

    late RuleEngine engine;

    setUp(() async {
      engine = RuleEngine();
      final envelope = await RuleCrypto.createSignedBaseRulesEnvelope(samplePayload);
      await engine.compile(json.encode(envelope));
    });

    test('compiles JSON rules and parses metadata correctly', () {
      expect(engine.version, equals('1.2.3'));
    });

    test('rejects base rules with invalid or missing Ed25519 signatures', () async {
      final invalidEngine = RuleEngine();
      
      // 1. Unsigned raw JSON
      final unsignedOk = await invalidEngine.compile(json.encode(samplePayload));
      expect(unsignedOk, isFalse);
      expect(invalidEngine.version, equals('0.0.0'));

      // 2. Corrupted signature
      final envelope = await RuleCrypto.createSignedBaseRulesEnvelope(samplePayload);
      envelope['signature'] = '0' * 128; // Tampered signature hex
      final tamperedOk = await invalidEngine.compile(json.encode(envelope));
      expect(tamperedOk, isFalse);
      expect(invalidEngine.version, equals('0.0.0'));
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

    test('dynamic user reinforcement rules signed with HMAC load successfully', () async {
      final customRule = const NotificationRule(
        id: 'rlhf-1001',
        category: 'msg',
        priority: 'critical',
        conditions: RuleCondition(keywords: ['custom_keyword']),
      );

      await engine.addReinforcementRule(customRule);

      final newEngine = RuleEngine();
      final envelope = await RuleCrypto.createSignedBaseRulesEnvelope(samplePayload);
      await newEngine.compile(json.encode(envelope));
      final loadedCustom = await newEngine.loadCustomRules();

      expect(loadedCustom, isTrue);

      final notif = AppNotification(
        id: '99',
        packageName: 'com.example',
        title: 'Test',
        content: 'Hello custom_keyword',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final matchResult = newEngine.match(notif);
      expect(matchResult, isNotNull);
      expect(matchResult!.ruleId, equals('rlhf-1001'));
      expect(matchResult.priority, equals('critical'));
    });

    test('tampered local dynamic rule fails HMAC verification and falls back safely', () async {
      final customRuleMap = {
        "id": "rlhf-tampered",
        "category": "override",
        "priority": "critical",
        "conditions": {
          "keywords": ["tampered"]
        }
      };

      // Create a tampered envelope with invalid HMAC
      final tamperedEnvelope = {
        "hmac": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "payload": {
          "rules": [customRuleMap]
        }
      };

      final verified = await RuleCrypto.verifyCustomRulesEnvelope(tamperedEnvelope);
      expect(verified, isNull);
    });

    test('rule verification overhead is under 15ms', () async {
      final envelope = await RuleCrypto.createSignedBaseRulesEnvelope(samplePayload);
      final envelopeStr = json.encode(envelope);

      final stopwatch = Stopwatch()..start();
      final testEngine = RuleEngine();
      await testEngine.compile(envelopeStr);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(15));
    });
  });
}
