import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

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

String createSignedEnvelope(Map<String, dynamic> payloadMap) {
  const seedHex = '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
  final privateKey = ed.newKeyFromSeed(_hexToBytes(seedHex));
  final payloadStr = json.encode(payloadMap);
  final signatureHex = _bytesToHex(ed.sign(privateKey, Uint8List.fromList(utf8.encode(payloadStr))));

  return json.encode({
    'author_key_id': 'scope-publisher-v1',
    'signature': signatureHex,
    'payload': payloadMap,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostAnalysisEngine', () {
    final sampleRulesMap = {
      "version": "1.0",
      "rules": [
        {
          "id": "bank_debit",
          "category": "finance",
          "priority": "critical",
          "conditions": {
            "keywords": ["debited", "spent"]
          }
        }
      ]
    };

    late GhostAnalysisEngine engine;

    setUp(() {
      engine = GhostAnalysisEngine();
      engine.ruleEngine.compile(createSignedEnvelope(sampleRulesMap));
    });

    test('orchestrates pipeline and classifies bank debit notification as critical', () async {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.example.bank',
        title: 'Transaction Alert',
        content: 'Your account has been debited Rs. 5,000 for your premium purchase.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('critical'));
      expect(analyzed.classifiedCategory, equals('finance'));
      expect(analyzed.explanation, contains('Amount: Found transaction amount'));
      expect(analyzed.latencyMs, isNotNull);
      expect(analyzed.extractedFeatures, isNotNull);
      expect(analyzed.extractedFeatures!['amount'], equals(5000.0));
    });

    test('orchestrates pipeline and classifies OTP messages as critical priority', () async {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'WhatsApp verification',
        content: 'Your registration code is 882715.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('critical'));
      expect(analyzed.extractedFeatures!['otp'], equals('882715'));
    });

    test('categorizes low priority promo keywords as low', () async {
      final notif = AppNotification(
        id: '3',
        packageName: 'com.amazon',
        title: 'Deals of the day',
        content: 'Get 25% off on shoes. Buy today!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('low'));
      expect(analyzed.classifiedCategory, equals('promo'));
    });

    test('initialization catches verification failures gracefully without crashing', () async {
      final testEngine = GhostAnalysisEngine();
      // Assets initialization might fail if asset is missing or invalid in mock test env,
      // but initialize() must catch and complete without crashing
      await expectLater(testEngine.initialize(), completes);
    });
  });
}
