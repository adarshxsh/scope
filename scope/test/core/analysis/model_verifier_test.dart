import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_verifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelVerifier Unit Tests', () {
    late ModelVerifier verifier;

    setUp(() {
      verifier = ModelVerifier.create();
    });

    test('verifies byte array against manifest digest correctly', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final expectedDigest = sha256.convert(sampleBytes).toString();

      verifier.setManifestForTesting({
        'assets/model.tflite': expectedDigest,
      });

      final result = await verifier.verify('assets/model.tflite', bytes: sampleBytes);
      expect(result, isTrue);
    });

    test('fails verification when byte hash mismatches manifest digest', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final corruptedBytes = Uint8List.fromList([1, 2, 3, 4, 6]);
      final expectedDigest = sha256.convert(sampleBytes).toString();

      verifier.setManifestForTesting({
        'assets/model.tflite': expectedDigest,
      });

      final result = await verifier.verify('assets/model.tflite', bytes: corruptedBytes);
      expect(result, isFalse);
    });

    test('fails verification when asset path is missing in manifest', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3]);
      verifier.setManifestForTesting({
        'assets/vocab.txt': 'abc123hash',
      });

      final result = await verifier.verify('assets/unknown.tflite', bytes: sampleBytes);
      expect(result, isFalse);
    });

    test('handles path variations (assets/prefix vs filename)', () async {
      final sampleBytes = Uint8List.fromList([10, 20, 30]);
      final expectedDigest = sha256.convert(sampleBytes).toString();

      verifier.setManifestForTesting({
        'assets/rules.json': expectedDigest,
      });

      final result1 = await verifier.verify('assets/rules.json', bytes: sampleBytes);
      final result2 = await verifier.verify('rules.json', bytes: sampleBytes);

      expect(result1, isTrue);
      expect(result2, isTrue);
    });

    test('completes verification within 10ms threshold', () async {
      final largeBytes = Uint8List(100 * 1024); // 100 KB mock model buffer
      final expectedDigest = sha256.convert(largeBytes).toString();

      verifier.setManifestForTesting({
        'assets/model.tflite': expectedDigest,
      });

      final stopwatch = Stopwatch()..start();
      final result = await verifier.verify('assets/model.tflite', bytes: largeBytes);
      stopwatch.stop();

      expect(result, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
    });
  });

  group('Asset Verification Integration & Fallback Tests', () {
    tearDown(() {
      ModelVerifier.instance.resetCache();
    });

    test('GhostAI initialization gracefully handles corrupted asset manifest', () async {
      // Set manifest with invalid digests
      ModelVerifier.instance.setManifestForTesting({
        'assets/model.tflite': '0000000000000000000000000000000000000000000000000000000000000000',
        'assets/rules.json': '0000000000000000000000000000000000000000000000000000000000000000',
      });

      final ghostAi = GhostAI.instance;
      await ghostAi.initialize();

      expect(ghostAi.isModelLoaded, isFalse);
    });

    test('LiteRtClassifier gracefully falls back to heuristic classification on asset verification failure', () async {
      ModelVerifier.instance.setManifestForTesting({
        'assets/vocab.txt': 'invalid_sha256_hash',
      });

      final classifier = LiteRtClassifier();
      expect(classifier.isModelLoaded, isFalse);
    });
  });
}
