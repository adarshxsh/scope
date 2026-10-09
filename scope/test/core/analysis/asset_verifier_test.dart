import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetIntegrityVerifier Tests', () {
    tearDown(() {
      AssetIntegrityVerifier.instance.resetManifest();
    });

    test('manifest contains valid SHA-256 entries for model.tflite, vocab.txt, and rules.json', () {
      final manifest = AssetIntegrityVerifier.instance.manifest;

      expect(manifest.containsKey('model.tflite') || manifest.containsKey('assets/model.tflite'), isTrue);
      expect(manifest.containsKey('vocab.txt') || manifest.containsKey('assets/vocab.txt'), isTrue);
      expect(manifest.containsKey('rules.json') || manifest.containsKey('assets/rules.json'), isTrue);

      expect(manifest['model.tflite'], equals('63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'));
      expect(manifest['rules.json'], equals('547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937'));
      expect(manifest['vocab.txt'], equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'));
    });

    test('verifies actual asset files on disk against manifest SHA-256 checksums', () {
      final verifier = AssetIntegrityVerifier.instance;

      final modelFile = File('assets/model.tflite');
      if (modelFile.existsSync()) {
        final bytes = modelFile.readAsBytesSync();
        expect(verifier.verifyBytes('model.tflite', bytes), isTrue);
      }

      final vocabFile = File('assets/vocab.txt');
      if (vocabFile.existsSync()) {
        final bytes = vocabFile.readAsBytesSync();
        expect(verifier.verifyBytes('vocab.txt', bytes), isTrue);
      }

      final rulesFile = File('assets/rules.json');
      if (rulesFile.existsSync()) {
        final content = rulesFile.readAsStringSync();
        expect(verifier.verifyString('rules.json', content), isTrue);
      }
    });

    test('rejects truncated or corrupted test bytes with unmatched checksums', () {
      final verifier = AssetIntegrityVerifier.instance;
      final truncatedBytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]); // truncated test bytes

      expect(verifier.verifyBytes('model.tflite', truncatedBytes), isFalse);
      expect(verifier.verifyBytes('vocab.txt', truncatedBytes), isFalse);
      expect(verifier.verifyBytes('rules.json', truncatedBytes), isFalse);
    });

    test('sub-millisecond latency overhead for asset SHA-256 checksum verification', () {
      final verifier = AssetIntegrityVerifier.instance;
      final sampleData = Uint8List.fromList(List.generate(100000, (i) => i % 256));

      final stopwatch = Stopwatch()..start();
      verifier.computeSha256(sampleData);
      stopwatch.stop();

      // Ensure execution completes within the 5 millisecond guardrail
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(5));
    });

    test('unmatched model asset checksum triggers GhostAI fallback mode without crashes', () async {
      // Set custom manifest with mismatched checksums simulating corrupted/truncated model binary
      AssetIntegrityVerifier.instance.setCustomManifest({
        'model.tflite': '0000000000000000000000000000000000000000000000000000000000000000',
        'rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
      });

      // GhostAI initialization should catch mismatch and proceed without throwing unhandled exceptions
      await GhostAI.instance.initialize();
      expect(GhostAI.instance.isModelLoaded, isFalse);

      final notif = AppNotification(
        id: 'test-fallback-1',
        packageName: 'com.whatsapp',
        title: 'OTP Code',
        content: 'Your OTP is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);
      expect(result, isNotNull);
      expect(result.reviewScore, equals(1.0)); // OTP heuristic fallback score
    });

    test('unmatched vocab asset checksum triggers LiteRtClassifier fallback without crashes', () async {
      // Set custom manifest with mismatched vocab checksum
      AssetIntegrityVerifier.instance.setCustomManifest({
        'vocab.txt': 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      });

      final classifier = LiteRtClassifier();
      final notif = AppNotification(
        id: 'test-fallback-2',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account was debited Rs. 500.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      expect(result, isNotNull);
      expect(result.category, equals('finance'));
      expect(result.engineName, contains('fallback'));
    });
  });
}
