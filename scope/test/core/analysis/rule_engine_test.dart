import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
import 'package:scope/core/analysis/embedded_keys.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const modulusHex =
      'a3e4b48adb7dcf64c02ef92cd17b09d3ba09b38c4f0f8718cbbbbb93bd420376'
      '702b89cdd55adc77d6324736d546d88778ff86563e8d1c6d09ce6938a9b45b29'
      '7039b5caedc1ce5772dff6bb6a10b9da103a04587a47a58d2a67b3cd4a1c1eb9'
      '4e4548072f8f62a961e78191522b368da42e8a0d63743768dc7ba737f8d0069a'
      '8a2812b4439470f3fad40355d2e282629a65bef87d3590052688635db41dc6f9'
      'f88b19bb69f4970482ef12e5e6d6121f5eeead0e21da111d49335b6991493a3e'
      'f4e4978b8abd5dce81f2c13c353dbc48a36b47c82f682c72990409993c8b47b8'
      'c1961995d03ac23012d1e97ddab5e09ac04d75d40fbe07efde0107e01c4e59f5';

  const privKeyHex =
      '0ae395dc38ef8fb133b49b410f4cf3aef1c815ba0f81aa59eb2556b5dee7ed27'
      '7815e872b8c76fe8f55e034dc11753291310b519f34f7851454ac5c26a420da1'
      '7fef91a4c12db47a2a6b776ee5c1e53b380346c9231cb202e24ba00e566b6e5e'
      '24f564eef749b946243757ac324fa530fd74cb1ecf1a08596af6bb3a34898bba'
      'ab144bd64dad1f049b84779bbf46067099d5602447e2f2fd55887a9fb5c3fc68'
      'aaf88d71bfdd5a46633e56fed3e66b2d1deb011200952267d85aa4d89db87cdc'
      '74c5ec451c62ecd8c718fc455fc99832714d20f18cc848d8a22ab38ca3b4cd7b'
      '08ddc1ba5c91b059e9cd8fee9f3e511deff863c5cb1b297a141b412d51fbab39';

  const sampleRulesMap = {
    'version': '1.2.3',
    'rules': [
      {
        'id': 'bank_debit',
        'category': 'finance',
        'priority': 'critical',
        'conditions': {
          'title_keywords': ['Alert', 'HDFC'],
          'keywords': ['debited', 'spent']
        }
      },
      {
        'id': 'whatsapp_mom',
        'category': 'msg',
        'priority': 'high',
        'conditions': {
          'packages': ['com.whatsapp'],
          'title_keywords': ['Mom']
        }
      },
      {
        'id': 'swiggy_promo',
        'category': 'promo',
        'priority': 'low',
        'conditions': {
          'keywords': ['50% off', 'discount']
        }
      }
    ]
  };

  String createSignedEnvelope({
    String signerId = 'scope-root-key-1',
    String algorithm = 'RSA-SHA256',
    Object? payload = sampleRulesMap,
    String? overrideSignature,
  }) {
    final payloadBytes = utf8.encode(
      payload is String ? payload : json.encode(payload),
    );

    final sig = overrideSignature ??
        CryptoVerifier.signRsaSha256(
          privateKeyHex: privKeyHex,
          modulusHex: modulusHex,
          payloadBytes: payloadBytes,
        );

    final map = {
      'signer_id': signerId,
      'algorithm': algorithm,
      'signature': sig,
      'payload': payload,
    };
    return json.encode(map);
  }

  group('RuleEngine - Basic Compilation & Matching', () {
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

    test('matches a debit transaction rule successfully', () {
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
  });

  group('RuleEngine - Signed Rule Database Compilation', () {
    late RuleEngine engine;

    setUp(() {
      engine = RuleEngine();
    });

    test('compileSigned compiles valid signed envelope under 5 ms', () {
      final signedEnvelopeStr = createSignedEnvelope();

      final sw = Stopwatch()..start();
      engine.compileSigned(signedEnvelopeStr);
      sw.stop();

      expect(engine.version, equals('1.2.3'));
      expect(sw.elapsedMilliseconds, lessThan(50));

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
    });

    test('compileSigned rejects envelope with corrupted signature', () {
      final invalidSignature = base64.encode(List<int>.filled(256, 0xAA));
      final tamperedSigEnvelope = createSignedEnvelope(overrideSignature: invalidSignature);

      expect(
        () => engine.compileSigned(tamperedSigEnvelope),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('compileSigned rejects envelope with tampered payload content', () {
      final validEnvelopeJson = createSignedEnvelope();
      final Map<String, dynamic> parsedMap = json.decode(validEnvelopeJson);

      // Tamper payload after signature was generated
      final tamperedPayload = Map<String, dynamic>.from(parsedMap['payload'] as Map);
      (tamperedPayload['rules'] as List)[0]['priority'] = 'low'; // altered priority
      parsedMap['payload'] = tamperedPayload;

      final tamperedEnvelopeStr = json.encode(parsedMap);

      expect(
        () => engine.compileSigned(tamperedEnvelopeStr),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('compileSigned rejects envelope with revoked key ID', () {
      final revokedEnvelope = createSignedEnvelope(signerId: 'scope-revoked-key-0');

      expect(
        () => engine.compileSigned(revokedEnvelope),
        throwsA(isA<SignatureVerificationException>().having(
          (e) => e.message,
          'message',
          contains('revoked'),
        )),
      );
    });

    test('compileSigned rejects envelope with missing signer key ID', () {
      final missingKeyEnvelope = createSignedEnvelope(signerId: 'unknown-key-999');

      expect(
        () => engine.compileSigned(missingKeyEnvelope),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('compileSigned rejects envelope with mismatched algorithm', () {
      final mismatchedAlgoEnvelope = createSignedEnvelope(algorithm: 'ED25519');

      expect(
        () => engine.compileSigned(mismatchedAlgoEnvelope),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('compileSigned rejects malformed envelope JSON missing signature', () {
      const malformedJson = '{"signer_id":"scope-root-key-1","algorithm":"RSA-SHA256"}';

      expect(
        () => engine.compileSigned(malformedJson),
        throwsA(isA<SignatureVerificationException>()),
      );
    });

    test('loadDefaultFallbackRules provides safe fallback heuristics', () {
      engine.loadDefaultFallbackRules();

      expect(engine.version, contains('fallback'));

      final otpNotif = AppNotification(
        id: 'otp1',
        packageName: 'com.whatsapp',
        title: 'Security Code',
        content: 'Your OTP code is 991823',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final match = engine.match(otpNotif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('fallback_otp'));
      expect(match.priority, equals('critical'));
    });
  });
}
