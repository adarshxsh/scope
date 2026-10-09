import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/crypto_utils.dart';
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
    late String sampleEnvelopeJson;

    setUp(() {
      engine = RuleEngine();
      final payloadObj = json.decode(sampleJson);
      final payloadBytes = utf8.encode(json.encode(payloadObj));
      final sig = CryptoUtils.signEd25519(messageBytes: payloadBytes);
      sampleEnvelopeJson = json.encode({
        'payload': payloadObj,
        'signature': sig,
        'key_id': CryptoUtils.publisherKeyId,
      });
      engine.compile(sampleEnvelopeJson);
    });

    test('compiles JSON rules and parses metadata correctly', () {
      expect(engine.version, equals('1.2.3'));
    });

    test('rejects raw unsigned JSON payload without envelope and throws IntegrityException', () {
      final unengine = RuleEngine();
      expect(
        () => unengine.compile(sampleJson),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('rejects envelope with missing signature and throws IntegrityException', () {
      final unengine = RuleEngine();
      final invalidEnvelope = json.encode({
        'payload': json.decode(sampleJson),
        'key_id': CryptoUtils.publisherKeyId,
      });
      expect(
        () => unengine.compile(invalidEnvelope),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('rejects envelope with tampered payload and throws IntegrityException', () {
      final unengine = RuleEngine();
      final payloadObj = json.decode(sampleJson) as Map<String, dynamic>;
      final payloadBytes = utf8.encode(json.encode(payloadObj));
      final sig = CryptoUtils.signEd25519(messageBytes: payloadBytes);

      // Tamper with payload
      payloadObj['version'] = '9.9.9';
      final tamperedEnvelope = json.encode({
        'payload': payloadObj,
        'signature': sig,
        'key_id': CryptoUtils.publisherKeyId,
      });

      expect(
        () => unengine.compile(tamperedEnvelope),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('rejects envelope with unknown key_id and throws IntegrityException', () {
      final unengine = RuleEngine();
      final payloadObj = json.decode(sampleJson);
      final payloadBytes = utf8.encode(json.encode(payloadObj));
      final sig = CryptoUtils.signEd25519(messageBytes: payloadBytes);

      final tamperedEnvelope = json.encode({
        'payload': payloadObj,
        'signature': sig,
        'key_id': 'unknown_key_99',
      });

      expect(
        () => unengine.compile(tamperedEnvelope),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('compileFallbackRules populates hardcoded safe default rules', () {
      final fallbackEngine = RuleEngine();
      fallbackEngine.compileFallbackRules();

      expect(fallbackEngine.version, equals('fallback-1.0.0'));
      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Verification Code',
        content: 'Your OTP is 123456',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final match = fallbackEngine.match(notif);
      expect(match, isNotNull);
      expect(match!.priority, equals('critical'));
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
  });
}
