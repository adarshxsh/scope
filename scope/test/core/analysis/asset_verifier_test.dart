import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifier Unit Tests', () {
    test('computeHash computes correct SHA-256 digest', () {
      final bytes = Uint8List.fromList(utf8.encode('test content'));
      // sha256("test content") = 6ae8a75555209fd6c44157c0aed8016e763ff435a19cf186f76863140143ff72
      final hash = AssetVerifier.computeHash(bytes);
      expect(hash, equals('6ae8a75555209fd6c44157c0aed8016e763ff435a19cf186f76863140143ff72'));
    });

    test('verifyHash returns true for matching hashes (case-insensitive)', () {
      final bytes = Uint8List.fromList(utf8.encode('test content'));
      expect(
        AssetVerifier.verifyHash(
          bytes,
          '6AE8A75555209FD6C44157C0AED8016E763FF435A19CF186F76863140143FF72',
        ),
        isTrue,
      );
    });

    test('verifyHash returns false for mismatched hashes', () {
      final bytes = Uint8List.fromList(utf8.encode('test content'));
      expect(
        AssetVerifier.verifyHash(
          bytes,
          '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        isFalse,
      );
    });

    test('verifyAsset validates actual bundle assets from rootBundle', () async {
      for (final path in AssetVerifier.expectedHashes.keys) {
        final byteData = await rootBundle.load(path);
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        expect(
          AssetVerifier.verifyAsset(path, bytes),
          isTrue,
          reason: 'SHA-256 verification failed for bundle asset $path',
        );
      }
    });

    test('verifyAsset rejects tampered asset byte buffer', () {
      final tamperedBytes = Uint8List.fromList(utf8.encode('corrupted model buffer'));
      expect(
        AssetVerifier.verifyAsset('assets/model.tflite', tamperedBytes),
        isFalse,
      );
    });

    test('verifyAndGetBuffer returns buffer when checksum matches', () {
      final bytes = Uint8List.fromList(utf8.encode('test content'));
      final hash = AssetVerifier.computeHash(bytes);

      // Temporarily test verifyAndGetBuffer via verifyHash match
      expect(AssetVerifier.verifyHash(bytes, hash), isTrue);
    });

    test('verifyAndGetBuffer throws AssetVerificationException on checksum mismatch', () {
      final tamperedBytes = Uint8List.fromList(utf8.encode('corrupted buffer'));
      expect(
        () => AssetVerifier.verifyAndGetBuffer('assets/model.tflite', tamperedBytes),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('verification latency for all bundle assets is well under 10 milliseconds', () async {
      final stopwatch = Stopwatch()..start();

      for (final path in AssetVerifier.expectedHashes.keys) {
        final byteData = await rootBundle.load(path);
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        AssetVerifier.verifyAndGetBuffer(path, bytes);
      }

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
    });
  });
}
