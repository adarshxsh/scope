import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_verifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelVerifier - Header Integrity', () {
    test('validateHeader returns true for valid TFLite header containing "TFL3" magic bytes', () {
      final validHeaderBytes = Uint8List.fromList([
        0x1C, 0x00, 0x00, 0x00,
        0x54, 0x46, 0x4C, 0x33, // "TFL3"
        0x14, 0x00, 0x20, 0x00,
      ]);
      expect(ModelVerifier.validateHeader(validHeaderBytes), isTrue);
    });

    test('validateHeader returns false for invalid header magic bytes', () {
      final invalidHeaderBytes = Uint8List.fromList([
        0x1C, 0x00, 0x00, 0x00,
        0x41, 0x42, 0x43, 0x44, // "ABCD"
        0x14, 0x00, 0x20, 0x00,
      ]);
      expect(ModelVerifier.validateHeader(invalidHeaderBytes), isFalse);
    });

    test('validateHeader returns false for truncated header buffer (< 8 bytes)', () {
      final truncatedBytes = Uint8List.fromList([0x1C, 0x00, 0x00, 0x00, 0x54]);
      expect(ModelVerifier.validateHeader(truncatedBytes), isFalse);
    });
  });

  group('ModelVerifier - SHA-256 Checksum Verification', () {
    final sampleData = Uint8List.fromList([
      0x1C, 0x00, 0x00, 0x00,
      0x54, 0x46, 0x4C, 0x33,
      0x01, 0x02, 0x03, 0x04,
    ]);
    final expectedHash = sha256.convert(sampleData).toString();

    test('computeSha256 calculates correct hex string', () {
      final computed = ModelVerifier.computeSha256(sampleData);
      expect(computed, equals(expectedHash));
    });

    test('verifyChecksum returns true for matching hash', () {
      expect(ModelVerifier.verifyChecksum(sampleData, expectedHash), isTrue);
      expect(ModelVerifier.verifyChecksum(sampleData, expectedHash.toUpperCase()), isTrue);
    });

    test('verifyChecksum returns false for mismatched hash', () {
      const wrongHash = '0000000000000000000000000000000000000000000000000000000000000000';
      expect(ModelVerifier.verifyChecksum(sampleData, wrongHash), isFalse);
    });
  });

  group('ModelVerifier - Digital Signature / HMAC Verification', () {
    final sampleBytes = Uint8List.fromList([
      0x1C, 0x00, 0x00, 0x00,
      0x54, 0x46, 0x4C, 0x33,
      0x05, 0x06, 0x07, 0x08,
    ]);
    final secretKey = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final hmac = Hmac(sha256, secretKey);
    final validSignature = hmac.convert(sampleBytes).bytes;

    test('verifySignature returns true for authentic signature', () {
      expect(ModelVerifier.verifySignature(sampleBytes, validSignature, secretKey), isTrue);
    });

    test('verifySignature returns false for tampered signature or key', () {
      final tamperedSig = List<int>.from(validSignature);
      tamperedSig[0] ^= 0xFF;
      expect(ModelVerifier.verifySignature(sampleBytes, tamperedSig, secretKey), isFalse);

      final wrongKey = Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]);
      expect(ModelVerifier.verifySignature(sampleBytes, validSignature, wrongKey), isFalse);
    });

    test('verifySignature returns false for empty input arguments', () {
      expect(ModelVerifier.verifySignature(sampleBytes, [], secretKey), isFalse);
      expect(ModelVerifier.verifySignature(sampleBytes, validSignature, []), isFalse);
    });
  });

  group('ModelVerifier - Full Pipeline (verifyBytes)', () {
    final validModelBytes = Uint8List.fromList([
      0x1C, 0x00, 0x00, 0x00,
      0x54, 0x46, 0x4C, 0x33, // TFL3
      0x10, 0x20, 0x30, 0x40,
    ]);
    final validHash = ModelVerifier.computeSha256(validModelBytes);

    test('returns valid result when header and checksum match', () {
      final result = ModelVerifier.verifyBytes(
        validModelBytes,
        expectedSha256: validHash,
      );
      expect(result.isValid, isTrue);
      expect(result.isHeaderValid, isTrue);
      expect(result.isChecksumValid, isTrue);
      expect(result.sha256Hash, equals(validHash));
    });

    test('returns invalid result on header magic mismatch', () {
      final corruptHeaderBytes = Uint8List.fromList([
        0x1C, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, // Invalid header
      ]);
      final result = ModelVerifier.verifyBytes(corruptHeaderBytes);
      expect(result.isValid, isFalse);
      expect(result.isHeaderValid, isFalse);
      expect(result.errorReason, contains('Invalid TFLite header'));
    });

    test('returns invalid result on SHA-256 checksum mismatch', () {
      final result = ModelVerifier.verifyBytes(
        validModelBytes,
        expectedSha256: 'a1b2c3d4e5f60000000000000000000000000000000000000000000000000000',
      );
      expect(result.isValid, isFalse);
      expect(result.isHeaderValid, isTrue);
      expect(result.isChecksumValid, isFalse);
      expect(result.errorReason, contains('SHA-256 checksum mismatch'));
    });
  });

  group('GhostAI Integration & Fallback Guardrails', () {
    test('GhostAI falls back safely when initialized with corrupted model asset bytes', () async {
      GhostAI.instance.resetForTesting();

      // Simulate asset bundle returning corrupted model bytes
      final mockBundle = _MockAssetBundle({
        'assets/model.tflite': Uint8List.fromList([1, 2, 3, 4]), // Bad header & size
        'assets/rules.json': '{"rules": []}',
      });

      await GhostAI.instance.initialize(
        bundle: mockBundle,
        expectedChecksum: ModelVerifier.defaultModelChecksum,
      );

      expect(GhostAI.instance.isModelVerified, isFalse);
      expect(GhostAI.instance.isModelLoaded, isFalse);
      expect(GhostAI.instance.lastVerificationError, isNotNull);

      // Verify inference gracefully degrades to heuristic classification without crashing
      final testNotif = AppNotification(
        id: 'test_corrupt_1',
        packageName: 'com.whatsapp',
        title: 'OTP Code',
        content: 'Your verification code is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(testNotif);
      expect(result.predictedScore, equals(1.0)); // Fallback OTP heuristic score
    });

    test('GhostAI falls back safely when checksum verification fails', () async {
      GhostAI.instance.resetForTesting();

      final validHeaderBytes = Uint8List.fromList([
        0x1C, 0x00, 0x00, 0x00,
        0x54, 0x46, 0x4C, 0x33, // TFL3
        0x11, 0x22, 0x33, 0x44,
      ]);

      final mockBundle = _MockAssetBundle({
        'assets/model.tflite': validHeaderBytes,
        'assets/rules.json': '{"rules": []}',
      });

      await GhostAI.instance.initialize(
        bundle: mockBundle,
        expectedChecksum: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      );

      expect(GhostAI.instance.isModelVerified, isFalse);
      expect(GhostAI.instance.isModelLoaded, isFalse);
      expect(GhostAI.instance.lastVerificationError, contains('SHA-256 checksum mismatch'));
    });
  });
}

class _MockAssetBundle extends CachingAssetBundle {
  final Map<String, dynamic> _assets;

  _MockAssetBundle(this._assets);

  @override
  Future<ByteData> load(String key) async {
    if (_assets.containsKey(key)) {
      final val = _assets[key];
      if (val is Uint8List) {
        return ByteData.sublistView(val);
      }
    }
    throw FlutterError('Asset not found: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (_assets.containsKey(key)) {
      final val = _assets[key];
      if (val is String) {
        return val;
      }
    }
    throw FlutterError('Asset not found: $key');
  }
}
