import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:scope/core/analysis/rule_crypto.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }
}

Uint8List _hexToBytes(String hex) {
  final cleanHex = hex.trim();
  final result = Uint8List(cleanHex.length ~/ 2);
  for (int i = 0; i < cleanHex.length; i += 2) {
    result[i ~/ 2] = int.parse(cleanHex.substring(i, i + 2), radix: 16);
  }
  return result;
}

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
}

String createSignedEnvelope(Map<String, dynamic> payloadMap, {String? customSignature}) {
  const seedHex = '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
  final privateKey = ed.newKeyFromSeed(_hexToBytes(seedHex));
  final payloadStr = json.encode(payloadMap);
  final signatureHex = customSignature ??
      _bytesToHex(ed.sign(privateKey, Uint8List.fromList(utf8.encode(payloadStr))));

  return json.encode({
    'author_key_id': 'scope-publisher-v1',
    'signature': signatureHex,
    'payload': payloadMap,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleRulesMap = {
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

  group('RuleEngine - Signature & Matching', () {
    late RuleEngine engine;
    late String signedSampleJson;

    setUp(() {
      engine = RuleEngine();
      signedSampleJson = createSignedEnvelope(sampleRulesMap);
      engine.compile(signedSampleJson);
    });

    test('compiles signed JSON rules envelope and parses metadata correctly', () {
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
  });

  group('RuleEngine - Cryptographic Security Rejections', () {
    late RuleEngine engine;

    setUp(() {
      engine = RuleEngine();
    });

    test('rejects unverified raw JSON string without envelope', () {
      const rawJson = '{"version": "1.0", "rules": []}';
      expect(() => engine.compile(rawJson), throwsA(isA<RuleSecurityException>()));
    });

    test('rejects tampered signature', () {
      final badSigEnvelope = createSignedEnvelope(
        sampleRulesMap,
        customSignature: '00' * 64, // Invalid 64-byte signature
      );
      expect(() => engine.compile(badSigEnvelope), throwsA(isA<RuleSecurityException>()));
    });

    test('rejects tampered payload', () {
      final envelopeObj = json.decode(createSignedEnvelope(sampleRulesMap)) as Map<String, dynamic>;
      // Modify payload after signature was generated
      envelopeObj['payload']['version'] = '9.9.9';
      final tamperedEnvelopeStr = json.encode(envelopeObj);

      expect(() => engine.compile(tamperedEnvelopeStr), throwsA(isA<RuleSecurityException>()));
    });
  });

  group('RuleEngine - HMAC Local RLHF Rule Persistence', () {
    late Directory tempDir;
    late RuleEngine engine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rule_engine_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
      engine = RuleEngine();
      engine.compile(createSignedEnvelope(sampleRulesMap));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves and loads custom RLHF rules with valid HMAC-SHA256 signature', () async {
      const customRule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'finance',
        priority: 'critical',
        conditions: RuleCondition(packages: ['com.mybank']),
      );

      await engine.addReinforcementRule(customRule);

      final newEngine = RuleEngine();
      newEngine.compile(createSignedEnvelope(sampleRulesMap));
      await newEngine.loadCustomRules();

      final notif = AppNotification(
        id: 'test-1',
        packageName: 'com.mybank',
        title: 'Bank Alert',
        content: 'Transfer update',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final match = newEngine.match(notif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('rlhf-custom-1'));
    });

    test('rejects tampered rlhf_rules.json with corrupted HMAC', () async {
      const customRule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'finance',
        priority: 'critical',
        conditions: RuleCondition(packages: ['com.mybank']),
      );

      await engine.addReinforcementRule(customRule);

      final file = File('${tempDir.path}/rlhf_rules.json');
      final content = await file.readAsString();
      final map = json.decode(content) as Map<String, dynamic>;
      map['hmac'] = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      await file.writeAsString(json.encode(map));

      final newEngine = RuleEngine();
      newEngine.compile(createSignedEnvelope(sampleRulesMap));

      expect(() async => await newEngine.loadCustomRules(), throwsA(isA<RuleSecurityException>()));
    });

    test('rejects tampered rlhf_rules.json payload with original HMAC', () async {
      const customRule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'finance',
        priority: 'critical',
        conditions: RuleCondition(packages: ['com.mybank']),
      );

      await engine.addReinforcementRule(customRule);

      final file = File('${tempDir.path}/rlhf_rules.json');
      final content = await file.readAsString();
      final map = json.decode(content) as Map<String, dynamic>;
      // Tamper payload without updating HMAC
      (map['payload'] as List).add({
        'id': 'rlhf-tampered',
        'category': 'promo',
        'priority': 'critical',
        'conditions': {'keywords': ['free']}
      });
      await file.writeAsString(json.encode(map));

      final newEngine = RuleEngine();
      newEngine.compile(createSignedEnvelope(sampleRulesMap));

      expect(() async => await newEngine.loadCustomRules(), throwsA(isA<RuleSecurityException>()));
    });
  });
}
