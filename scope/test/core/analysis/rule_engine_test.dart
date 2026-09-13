import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory testDir;
  FakePathProviderPlatform(this.testDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return testDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuleEngine', () {
    const String sampleJson = '''
    {
      "version": "1.0.0",
      "timestamp": 1789263929995,
      "key_id": "scope-prod-key-1",
      "signature_algorithm": "Ed25519",
      "signature": "t1YjxdLuX8VzWNyoB8uFifOjMblc6lRMsQ8GLGSovWCTL2S2z5d2HUR8cwrYhxfWJ1zqDoE/buSbEOqVMGq0Dg==",
      "payload": {
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
    }
    ''';

    late RuleEngine engine;

    setUp(() async {
      engine = RuleEngine();
      await engine.compile(sampleJson);
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
        packageName: 'com.hdfc.mobilebanking',
        title: 'Daily Update',
        content: 'Your account has been debited Rs. 15,000.',
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

    group('Cryptographic Verification & Security Tests', () {
      test('verifies valid Ed25519 signature manifest successfully', () async {
        final testEngine = RuleEngine();
        await testEngine.compile(sampleJson);
        expect(testEngine.version, equals('1.2.3'));
        expect(testEngine.rules.length, equals(3));
      });

      test('throws RuleVerificationException and falls back to safe default rules when payload is tampered', () async {
        final tamperedJson = sampleJson.replaceAll('debited', 'hacked_debited');
        final testEngine = RuleEngine();

        await expectLater(
          testEngine.compile(tamperedJson),
          throwsA(isA<RuleVerificationException>()),
        );

        expect(testEngine.version, equals('0.0.0-safe-fallback'));
        expect(testEngine.rules.isNotEmpty, isTrue);
        expect(testEngine.rules.any((r) => r.id == 'default_otp_security'), isTrue);
      });

      test('throws RuleVerificationException and falls back to safe default rules when signature is forged or invalid', () async {
        final map = json.decode(sampleJson) as Map<String, dynamic>;
        map['signature'] = base64Encode(List<int>.filled(64, 0));
        final forgedJson = json.encode(map);

        final testEngine = RuleEngine();

        await expectLater(
          testEngine.compile(forgedJson),
          throwsA(isA<RuleVerificationException>()),
        );

        expect(testEngine.version, equals('0.0.0-safe-fallback'));
        expect(testEngine.rules.any((r) => r.id == 'default_finance_debit'), isTrue);
      });

      test('throws RuleVerificationException and falls back when mandatory signature envelope headers are missing', () async {
        const unsignedJson = '''
        {
          "version": "1.0.0",
          "rules": [
            {
              "id": "unauthorized_rule",
              "category": "sys",
              "priority": "critical",
              "conditions": { "keywords": ["override"] }
            }
          ]
        }
        ''';

        final testEngine = RuleEngine();

        await expectLater(
          testEngine.compile(unsignedJson),
          throwsA(isA<RuleVerificationException>()),
        );

        expect(testEngine.version, equals('0.0.0-safe-fallback'));
        expect(testEngine.rules.any((r) => r.id == 'unauthorized_rule'), isFalse);
        expect(testEngine.rules.any((r) => r.id == 'default_otp_security'), isTrue);
      });

      test('supports key rotation via key_id attributes', () async {
        final ed25519 = Ed25519();
        final rotationKeyPair = await ed25519.newKeyPair();
        final rotationPubKey = await rotationKeyPair.extractPublicKey();
        final rotationPubKeyBase64 = base64Encode(rotationPubKey.bytes);

        const keyId = 'scope-rotation-key-99';
        CryptoVerifier.addTrustedPublicKey(keyId, rotationPubKeyBase64);

        final payloadMap = {
          'version': '2.0.0-rotated',
          'rules': [
            {
              'id': 'rotated_rule',
              'category': 'sys',
              'priority': 'critical',
              'conditions': {'keywords': ['rotation']}
            }
          ]
        };

        final payloadBytes = utf8.encode(jsonEncode(payloadMap));
        final sigBase64 = await CryptoVerifier.signEd25519Payload(
          payloadBytes: payloadBytes,
          keyPair: rotationKeyPair,
        );

        final rotatedManifest = {
          'version': '1.0.0',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'key_id': keyId,
          'signature_algorithm': 'Ed25519',
          'signature': sigBase64,
          'payload': payloadMap,
        };

        final testEngine = RuleEngine();
        await testEngine.compile(json.encode(rotatedManifest));

        expect(testEngine.version, equals('2.0.0-rotated'));
        expect(testEngine.rules.length, equals(1));
        expect(testEngine.rules.first.id, equals('rotated_rule'));
      });

      test('secures custom RLHF rules with device-bound HMAC-SHA256 and rejects out-of-band tampered files', () async {
        final tempDir = Directory.systemTemp.createTempSync('rlhf_test_');
        PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);

        try {
          final testEngine = RuleEngine();
          await testEngine.compile(sampleJson);

          final customRule = NotificationRule(
            id: 'rlhf-custom-1',
            category: 'sys',
            priority: 'critical',
            conditions: const RuleCondition(keywords: ['custom_rlhf_keyword']),
          );

          await testEngine.addReinforcementRule(customRule);

          final rlhfFile = File('${tempDir.path}/rlhf_rules.json');
          expect(await rlhfFile.exists(), isTrue);

          final content = await rlhfFile.readAsString();
          final rlhfMap = json.decode(content) as Map<String, dynamic>;
          expect(rlhfMap['signature_algorithm'], equals('HMAC-SHA256'));
          expect(rlhfMap['signature'], isNotNull);

          // Verify loading valid device-signed custom rules
          final reloadEngine = RuleEngine();
          await reloadEngine.compile(sampleJson);
          await reloadEngine.loadCustomRules();

          final matched = reloadEngine.match(
            AppNotification(
              id: '99',
              packageName: 'com.app',
              title: 'Test',
              content: 'Matches custom_rlhf_keyword',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          expect(matched, isNotNull);
          expect(matched!.ruleId, equals('rlhf-custom-1'));

          // Test out-of-band tampering rejection
          rlhfMap['payload'][0]['conditions']['keywords'] = ['tampered_out_of_band'];
          await rlhfFile.writeAsString(json.encode(rlhfMap));

          final tamperedReloadEngine = RuleEngine();
          await tamperedReloadEngine.compile(sampleJson);
          await tamperedReloadEngine.loadCustomRules();

          expect(tamperedReloadEngine.rules.any((r) => r.id == 'rlhf-custom-1'), isFalse);
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('cryptographic verification executes in under 10ms', () async {
        final testEngine = RuleEngine();
        final stopwatch = Stopwatch()..start();
        await testEngine.compile(sampleJson);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(10));
      });
    });
  });
}
