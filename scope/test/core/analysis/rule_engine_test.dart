import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('RuleEngine', () {
    final Map<String, dynamic> samplePayload = {
      'rules': [
        {
          'id': 'bank_debit',
          'category': 'finance',
          'priority': 'critical',
          'conditions': {
            'title_keywords': ['Alert', 'HDFC'],
            'keywords': ['debited', 'spent'],
          },
        },
        {
          'id': 'whatsapp_mom',
          'category': 'msg',
          'priority': 'high',
          'conditions': {
            'packages': ['com.whatsapp'],
            'title_keywords': ['Mom'],
          },
        },
        {
          'id': 'swiggy_promo',
          'category': 'promo',
          'priority': 'low',
          'conditions': {
            'keywords': ['50% off', 'discount'],
          },
        },
      ],
    };

    late String validSignedJson;
    late RuleEngine engine;

    setUp(() {
      final envelope = RuleEngine.createSignedEnvelope(
        samplePayload,
        version: '1.2.3',
      );
      validSignedJson = json.encode(envelope);

      engine = RuleEngine();
      engine.compile(validSignedJson);
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

    group('Integrity and HMAC verification', () {
      test('throws IntegrityException when missing envelope integrity metadata', () {
        const unsignedJson = '{"version": "1.0.0", "rules": []}';
        expect(
          () => engine.compile(unsignedJson),
          throwsA(isA<IntegrityException>()),
        );
      });

      test('throws IntegrityException when payload digest is corrupted', () {
        final envelope = RuleEngine.createSignedEnvelope(samplePayload, version: '1.2.3');
        envelope['digest'] = 'bad_digest_hash_000000000000000000000000000000000000000000000000';

        expect(
          () => engine.compile(json.encode(envelope)),
          throwsA(isA<IntegrityException>()),
        );
      });

      test('throws IntegrityException when HMAC signature is invalid', () {
        final envelope = RuleEngine.createSignedEnvelope(samplePayload, version: '1.2.3');
        envelope['signature'] = 'bad_signature_hash_0000000000000000000000000000000000000000000';

        expect(
          () => engine.compile(json.encode(envelope)),
          throwsA(isA<IntegrityException>()),
        );
      });

      test('falls back to default rules on integrity failure and matches OTP fallback', () {
        final testEngine = RuleEngine();
        expect(
          () => testEngine.compile('{"version": "1.0.0", "rules": []}'),
          throwsA(isA<IntegrityException>()),
        );

        final otpNotif = AppNotification(
          id: 'fallback-1',
          packageName: 'com.whatsapp',
          title: 'OTP',
          content: 'Your verification code is 123456.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = testEngine.match(otpNotif);
        expect(result, isNotNull);
        expect(result!.ruleId, equals('otp_security'));
      });

      test('compilation latency is under 2 milliseconds', () {
        final testEngine = RuleEngine();
        final stopwatch = Stopwatch()..start();
        testEngine.compile(validSignedJson);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(2));
      });
    });
  });
}
