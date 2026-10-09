import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_integrity_registry.dart';
import 'package:scope/core/analysis/asset_verifier.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
import 'package:scope/core/analysis/rule_crypto.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/rule_schema_validator.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetIntegrityRegistry Tests', () {
    tearDown(() {
      AssetIntegrityRegistry.resetToDefaults();
    });

    test('Registry contains expected ground-truth SHA-256 digests', () {
      expect(
        AssetIntegrityRegistry.getExpectedChecksum('assets/rules.json'),
        equals('547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937'),
      );
      expect(
        AssetIntegrityRegistry.getExpectedChecksum('assets/model.tflite'),
        equals('63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'),
      );
      expect(
        AssetIntegrityRegistry.getExpectedChecksum('assets/vocab.txt'),
        equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'),
      );
    });

    test('Allows custom asset registration and reset', () {
      AssetIntegrityRegistry.registerAsset('assets/custom_rules.json', 'abc123hash');
      expect(
        AssetIntegrityRegistry.getExpectedChecksum('assets/custom_rules.json'),
        equals('abc123hash'),
      );

      AssetIntegrityRegistry.resetToDefaults();
      expect(
        AssetIntegrityRegistry.isRegistered('assets/custom_rules.json'),
        isFalse,
      );
    });
  });

  group('AssetVerifier Tests', () {
    test('verifyString succeeds when SHA-256 hash matches', () {
      const content = 'hello world';
      final expectedSha256 = sha256.convert(utf8.encode(content)).toString();

      expect(AssetVerifier.verifyString(content, expectedSha256), isTrue);
    });

    test('verifyString throws AssetVerificationException on checksum mismatch', () {
      const content = 'hello world';
      const wrongSha256 = '0000000000000000000000000000000000000000000000000000000000000000';

      expect(
        () => AssetVerifier.verifyString(content, wrongSha256, assetPath: 'assets/rules.json'),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('verifyBytes throws AssetVerificationException on mismatch', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      const badHash = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

      expect(
        () => AssetVerifier.verifyBytes(bytes, badHash),
        throwsA(isA<AssetVerificationException>()),
      );
    });
  });

  group('RuleCrypto and CryptoVerifier Tests', () {
    test('RuleCrypto derives device key deterministically', () {
      final key1 = RuleCrypto.deriveDeviceKey('device1');
      final key2 = RuleCrypto.deriveDeviceKey('device1');
      final key3 = RuleCrypto.deriveDeviceKey('device2');

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
    });

    test('RuleCrypto computes and verifies HMAC-SHA256 signatures', () {
      final key = RuleCrypto.deriveDeviceKey();
      const payload = '{"version": "1.0.0", "rules": []}';

      final sigHex = RuleCrypto.computeHmacHex(payload, key);
      expect(RuleCrypto.verifyHmac(payload, sigHex, key), isTrue);
      expect(RuleCrypto.verifyHmac(payload, 'bad_sig', key), isFalse);
    });

    test('CryptoVerifier verifies HMAC envelope signatures', () {
      final key = RuleCrypto.deriveDeviceKey();
      const payload = '{"version": "1.0.0", "rules": []}';
      final sigHex = RuleCrypto.computeHmacHex(payload, key);

      final envelope = {
        'signature': sigHex,
        'algorithm': 'hmac-sha256',
        'payload': payload,
      };

      expect(CryptoVerifier.verifyEnvelope(envelope, hmacKey: key), isTrue);

      final tamperedEnvelope = {
        'signature': sigHex,
        'algorithm': 'hmac-sha256',
        'payload': '{"version": "1.0.0", "rules": [{"id": "hacked"}]}',
      };

      expect(CryptoVerifier.verifyEnvelope(tamperedEnvelope, hmacKey: key), isFalse);
    });
  });

  group('RuleSchemaValidator Tests', () {
    test('Validates and sanitizes rule condition terms using RegExp.escape', () {
      const rule = NotificationRule(
        id: 'test_rule',
        category: 'msg',
        priority: 'high',
        conditions: RuleCondition(
          keywords: ['50% off*', 'call (me)'],
        ),
      );

      final validated = RuleSchemaValidator.validateAndSanitize(rule);
      expect(validated.conditions.keywords, contains('50% off\\*'));
      expect(validated.conditions.keywords, contains('call \\(me\\)'));
    });

    test('Demotes custom user rule critical priority to high', () {
      const customRule = NotificationRule(
        id: 'rlhf-user-override',
        category: 'sys',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['override'],
        ),
      );

      final validated = RuleSchemaValidator.validateAndSanitize(
        customRule,
        isCustomUserRule: true,
      );

      expect(validated.priority, equals('high'));
    });

    test('Throws RuleSchemaValidationException when rule conditions are empty', () {
      const emptyRule = NotificationRule(
        id: 'empty_rule',
        category: 'promo',
        priority: 'low',
        conditions: RuleCondition(),
      );

      expect(
        () => RuleSchemaValidator.validateAndSanitize(emptyRule),
        throwsA(isA<RuleSchemaValidationException>()),
      );
    });
  });

  group('RuleEngine Integrity and Signing Integration Tests', () {
    late RuleEngine engine;

    setUp(() {
      engine = RuleEngine();
    });

    test('compileSigned compiles valid payload with SHA-256 matching registered checksum', () {
      const validJson = '''
      {
        "version": "1.0.0",
        "rules": [
          {
            "id": "signed_otp",
            "category": "sys",
            "priority": "critical",
            "conditions": {
              "keywords": ["verification code"]
            }
          }
        ]
      }
      ''';

      final validSha256 = sha256.convert(utf8.encode(validJson)).toString();
      engine.compileSigned(validJson, expectedSha256: validSha256);

      expect(engine.version, equals('1.0.0'));

      final notif = AppNotification(
        id: '100',
        packageName: 'com.auth',
        title: 'Security',
        content: 'Your verification code is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final match = engine.match(notif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('signed_otp'));
      expect(match.priority, equals('critical'));
    });

    test('compileSigned throws AssetVerificationException if SHA-256 mismatch', () {
      const jsonStr = '{"version": "1.0.0", "rules": []}';
      const wrongSha256 = '0000000000000000000000000000000000000000000000000000000000000000';

      expect(
        () => engine.compileSigned(jsonStr, expectedSha256: wrongSha256),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('compileSigned validates cryptographic envelope and rejects tampered envelopes', () {
      final key = RuleCrypto.deriveDeviceKey();
      final rawRulesJson = jsonEncode({
        'version': '2.0.0',
        'rules': [
          {
            'id': 'finance_debit',
            'category': 'finance',
            'priority': 'critical',
            'conditions': {
              'keywords': ['debited']
            }
          }
        ]
      });

      final hmacSig = RuleCrypto.computeHmacHex(rawRulesJson, key);

      final envelopeJson = jsonEncode({
        'signature': hmacSig,
        'algorithm': 'hmac-sha256',
        'payload': rawRulesJson,
      });

      // Valid compilation
      engine.compileSigned(envelopeJson);
      expect(engine.version, equals('2.0.0'));

      // Tampered envelope compilation
      final tamperedEnvelopeJson = jsonEncode({
        'signature': hmacSig,
        'algorithm': 'hmac-sha256',
        'payload': '{"version": "9.9.9", "rules": []}',
      });

      expect(
        () => engine.compileSigned(tamperedEnvelopeJson),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('Reinforcement RLHF rule demotes critical to high and signs custom rules', () {
      const baseJson = '''
      {
        "version": "1.0.0",
        "rules": [
          {
            "id": "otp_security",
            "category": "sys",
            "priority": "critical",
            "conditions": {
              "keywords": ["otp"]
            }
          }
        ]
      }
      ''';

      engine.compile(baseJson);

      const rlhfRule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'msg',
        priority: 'critical', // Will be demoted to 'high'
        conditions: RuleCondition(
          packages: ['com.whatsapp'],
          keywords: ['urgent'],
        ),
      );

      engine.addReinforcementRule(rlhfRule);

      final notif = AppNotification(
        id: '200',
        packageName: 'com.whatsapp',
        title: 'Message',
        content: 'otp urgent call me',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final match = engine.match(notif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('otp_security')); // System rules evaluated first

      final customNotif = AppNotification(
        id: '201',
        packageName: 'com.whatsapp',
        title: 'Message',
        content: 'urgent meeting',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final customMatch = engine.match(customNotif);
      expect(customMatch, isNotNull);
      expect(customMatch!.ruleId, equals('rlhf-custom-1'));
      expect(customMatch.priority, equals('high')); // Priority demoted from critical to high
    });
  });
}
