import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifier Unit Tests', () {
    final sampleContent = utf8.encode('Hello SCOPE Asset Verifier!');
    final sampleBytes = Uint8List.fromList(sampleContent);
    final expectedHash = AssetVerifier.computeSha256(sampleBytes);

    test('computeSha256 returns valid hex string', () {
      final hash = AssetVerifier.computeSha256(sampleBytes);
      expect(hash, isNotEmpty);
      expect(hash.length, equals(64));
    });

    test('verifyBuffer returns true when buffer digest matches manifest', () {
      final manifest = {
        'assets/model.tflite': expectedHash,
      };

      final isValid = AssetVerifier.verifyBuffer(
        sampleBytes,
        'assets/model.tflite',
        manifest: manifest,
      );

      expect(isValid, isTrue);
    });

    test('verifyBuffer returns false when buffer bytes are tampered', () {
      final tamperedBytes = Uint8List.fromList(utf8.encode('Tampered content!'));
      final manifest = {
        'assets/model.tflite': expectedHash,
      };

      final isValid = AssetVerifier.verifyBuffer(
        tamperedBytes,
        'assets/model.tflite',
        manifest: manifest,
      );

      expect(isValid, isFalse);
    });

    test('verifyBuffer returns false when asset key is missing in manifest', () {
      final manifest = {
        'assets/other_model.tflite': expectedHash,
      };

      final isValid = AssetVerifier.verifyBuffer(
        sampleBytes,
        'assets/model.tflite',
        manifest: manifest,
      );

      expect(isValid, isFalse);
    });

    test('verifyBuffer handles empty buffer gracefully', () {
      final manifest = {
        'assets/model.tflite': expectedHash,
      };

      final isValid = AssetVerifier.verifyBuffer(
        Uint8List(0),
        'assets/model.tflite',
        manifest: manifest,
      );

      expect(isValid, isFalse);
    });

    test('asset integrity verification completes within 15 ms limit', () {
      final manifest = {
        'assets/model.tflite': expectedHash,
      };

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        AssetVerifier.verifyBuffer(sampleBytes, 'assets/model.tflite', manifest: manifest);
      }
      stopwatch.stop();

      // Average execution time should be under 15ms
      expect(stopwatch.elapsedMilliseconds, lessThan(15));
    });
  });
}
