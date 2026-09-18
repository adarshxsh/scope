import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_integrity_verifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetIntegrityVerifier Tests', () {
    late AssetIntegrityVerifier verifier;

    setUp(() {
      verifier = AssetIntegrityVerifier.instance;
      verifier.reset();
    });

    test('Valid manifest and byte hash verification passes', () {
      final sampleBytes = Uint8List.fromList(utf8.encode('hello world scope asset content'));
      final expectedHash = sha256.convert(sampleBytes).toString();

      final manifestData = {
        'version': '1.0',
        'assets': {
          'assets/test_asset.txt': {
            'sha256': expectedHash,
            'length': sampleBytes.length,
          }
        }
      };

      verifier.loadManifestFromMap(manifestData);

      final result = verifier.verifyBytes('assets/test_asset.txt', sampleBytes);

      expect(result.status, equals(AssetIntegrityStatus.verified));
      expect(result.isVerified, isTrue);
      expect(result.actualHash, equals(expectedHash));
      expect(result.actualLength, equals(sampleBytes.length));
      expect(result.errorMessage, isNull);
    });

    test('Checksum mismatch returns corrupted status', () {
      final originalBytes = Uint8List.fromList(utf8.encode('original asset content'));
      final corruptedBytes = Uint8List.fromList(utf8.encode('modified asset content')); // Same length (22 bytes)
      final expectedHash = sha256.convert(originalBytes).toString();

      final manifestData = {
        'version': '1.0',
        'assets': {
          'assets/model.tflite': {
            'sha256': expectedHash,
            'length': originalBytes.length,
          }
        }
      };

      verifier.loadManifestFromMap(manifestData);

      final result = verifier.verifyBytes('assets/model.tflite', corruptedBytes);

      expect(result.status, equals(AssetIntegrityStatus.corrupted));
      expect(result.isVerified, isFalse);
      expect(result.errorMessage, contains('checksum mismatch'));
    });

    test('Length mismatch returns corrupted status', () {
      final sampleBytes = Uint8List.fromList(utf8.encode('short content'));
      final manifestData = {
        'version': '1.0',
        'assets': {
          'assets/vocab.txt': {
            'sha256': sha256.convert(sampleBytes).toString(),
            'length': 99999, // Mismatched length
          }
        }
      };

      verifier.loadManifestFromMap(manifestData);

      final result = verifier.verifyBytes('assets/vocab.txt', sampleBytes);

      expect(result.status, equals(AssetIntegrityStatus.corrupted));
      expect(result.isVerified, isFalse);
      expect(result.errorMessage, contains('Byte length mismatch'));
    });

    test('Missing manifest returns manifestMissing status', () {
      final bytes = Uint8List.fromList(utf8.encode('any bytes'));
      // Verifier is in reset state (manifest missing)
      final result = verifier.verifyBytes('assets/rules.json', bytes);

      expect(result.status, equals(AssetIntegrityStatus.manifestMissing));
      expect(result.isVerified, isFalse);
    });

    test('Unregistered asset in manifest returns assetMissing status', () {
      final bytes = Uint8List.fromList(utf8.encode('unregistered asset'));
      final manifestData = {
        'version': '1.0',
        'assets': {
          'assets/known_asset.txt': {
            'sha256': '123456',
            'length': 10,
          }
        }
      };

      verifier.loadManifestFromMap(manifestData);

      final result = verifier.verifyBytes('assets/unknown_asset.txt', bytes);

      expect(result.status, equals(AssetIntegrityStatus.assetMissing));
      expect(result.isVerified, isFalse);
    });

    test('SHA-256 verification completes quickly for asset model payloads', () {
      // 100KB asset model payload (typical model file size)
      final modelBytes = Uint8List(100 * 1024);
      for (int i = 0; i < modelBytes.length; i += 4096) {
        modelBytes[i] = i % 256;
      }
      final hash = sha256.convert(modelBytes).toString();

      final manifestData = {
        'version': '1.0',
        'assets': {
          'assets/large_model.tflite': {
            'sha256': hash,
            'length': modelBytes.length,
          }
        }
      };

      verifier.loadManifestFromMap(manifestData);

      final stopwatch = Stopwatch()..start();
      final result = verifier.verifyBytes('assets/large_model.tflite', modelBytes);
      stopwatch.stop();

      expect(result.isVerified, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('GhostAI and LiteRtClassifier Integration & Fallback Tests', () {
    setUp(() {
      AssetIntegrityVerifier.instance.reset();
    });

    test('GhostAI falls back gracefully when model asset is corrupted', () async {
      // Set manifest with dummy expected hash
      AssetIntegrityVerifier.instance.loadManifestFromMap({
        'version': '1.0',
        'assets': {
          'assets/model.tflite': {
            'sha256': '0000000000000000000000000000000000000000000000000000000000000000',
            'length': 100,
          },
          'assets/rules.json': {
            'sha256': '1111111111111111111111111111111111111111111111111111111111111111',
            'length': 100,
          }
        }
      });

      // Initialize GhostAI (verification will fail because loaded assets don't match dummy manifest)
      await GhostAI.instance.initialize();

      expect(GhostAI.instance.isModelLoaded, isFalse);

      final notif = AppNotification(
        id: 'test_1',
        packageName: 'com.whatsapp',
        title: 'OTP',
        content: 'Your verification code is 1234',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);

      // Prediction still succeeds using heuristic fallback without crashing
      expect(result.reviewScore, greaterThanOrEqualTo(0.0));
      expect(result.reviewScore, lessThanOrEqualTo(1.0));
    });

    test('LiteRtClassifier falls back gracefully when vocab asset is corrupted', () async {
      AssetIntegrityVerifier.instance.loadManifestFromMap({
        'version': '1.0',
        'assets': {
          'assets/vocab.txt': {
            'sha256': 'badhash00000000000000000000000000000000000000000000000000000000',
            'length': 5,
          }
        }
      });

      final classifier = LiteRtClassifier();
      await classifier.initialize();

      final notif = AppNotification(
        id: 'test_2',
        packageName: 'com.bank.app',
        title: 'Transaction',
        content: 'Rs. 500 debited from account',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.category, equals('finance'));
      expect(result.engineName, contains('fallback'));
    });
  });
}
