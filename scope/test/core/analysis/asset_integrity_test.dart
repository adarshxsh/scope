import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_integrity.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Asset Integrity Verification', () {
    test('expectedHashes map contains correct SHA-256 ground truth entries', () {
      expect(expectedHashes.containsKey('assets/model.tflite'), isTrue);
      expect(expectedHashes.containsKey('assets/vocab.txt'), isTrue);
      expect(expectedHashes.containsKey('assets/rules.json'), isTrue);

      expect(expectedHashes['assets/model.tflite'], equals('63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'));
      expect(expectedHashes['assets/vocab.txt'], equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'));
      expect(expectedHashes['assets/rules.json'], equals('547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937'));
    });

    test('AssetIntegrity.computeSha256 calculates accurate digest', () {
      final bytes = 'Hello World'.codeUnits;
      // sha256("Hello World") = a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e
      final hash = AssetIntegrity.computeSha256(bytes);
      expect(hash, equals('a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e'));
    });

    test('AssetIntegrity.verify validates matching hash and rejects mismatched hash', () {
      final bytes = 'Hello World'.codeUnits;
      final customHashes = {
        'assets/test.txt': 'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e',
      };

      expect(AssetIntegrity.verify('assets/test.txt', bytes, customHashes: customHashes), isTrue);

      final invalidHashes = {
        'assets/test.txt': '0000000000000000000000000000000000000000000000000000000000000000',
      };
      expect(AssetIntegrity.verify('assets/test.txt', bytes, customHashes: invalidHashes), isFalse);
    });

    test('LiteRtClassifier rejects corrupted assets and gracefully executes fallback heuristic', () async {
      final corruptHashes = {
        'assets/vocab.txt': 'invalid_vocab_hash',
        'assets/model.tflite': 'invalid_model_hash',
      };

      final classifier = LiteRtClassifier();
      await classifier.initialize(customHashes: corruptHashes);

      expect(classifier.isModelLoaded, isFalse);

      final notif = AppNotification(
        id: 'corrupt-test',
        packageName: 'com.amazon.shopping',
        title: 'Special Offer',
        content: 'Get 50% off on electronics during big sale!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.category, equals('promo'));
      expect(result.engineName, contains('fallback'));
      expect(result.matchedSignals, contains('Model asset invalid or uninitialized'));
    });

    test('GhostAI rejects corrupted model asset and keeps isModelLoaded as false', () async {
      GhostAI.instance.resetForTest();

      final corruptHashes = {
        'assets/model.tflite': 'bad_hash_value',
        'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
      };

      await GhostAI.instance.initialize(customHashes: corruptHashes);

      expect(GhostAI.instance.isModelLoaded, isFalse);
    });
  });
}
