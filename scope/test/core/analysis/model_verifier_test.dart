import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_verifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Construct mock valid TFLite header buffer: 4 dummy bytes + 'TFL3' + payload
  Uint8List buildMockTfliteBuffer({List<int>? payload}) {
    final header = [0x00, 0x00, 0x00, 0x00, 0x54, 0x46, 0x4C, 0x33]; // TFL3 at 4..7
    final body = payload ?? List<int>.generate(32, (i) => i * 2);
    return Uint8List.fromList([...header, ...body]);
  }

  group('ModelVerifier Tests', () {
    test('validates correct TFLite buffer and matching SHA-256 checksum', () {
      final buffer = buildMockTfliteBuffer();
      final expectedHash = sha256.convert(buffer).toString();

      final result = ModelVerifier.verifyModelBytes(
        buffer,
        expectedChecksum: expectedHash,
      );

      expect(result.isValid, isTrue);
      expect(result.status, equals('verified'));
      expect(result.checksum, equals(expectedHash.toLowerCase()));
      expect(result.errorMessage, isNull);
    });

    test('fails verification on SHA-256 checksum mismatch', () {
      final buffer = buildMockTfliteBuffer();
      const wrongHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final result = ModelVerifier.verifyModelBytes(
        buffer,
        expectedChecksum: wrongHash,
      );

      expect(result.isValid, isFalse);
      expect(result.status, equals('checksum_mismatch'));
      expect(result.errorMessage, contains('SHA-256 checksum mismatch'));
    });

    test('fails verification on invalid TFLite header magic bytes', () {
      final invalidBuffer = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x00, 0x42, 0x41, 0x44, 0x21, // "BAD!" instead of "TFL3"
        0x01, 0x02, 0x03, 0x04
      ]);

      final result = ModelVerifier.verifyModelBytes(invalidBuffer);

      expect(result.isValid, isFalse);
      expect(result.status, equals('invalid_header'));
      expect(result.errorMessage, contains('Invalid TensorFlow Lite header identifier'));
    });

    test('fails verification on empty or short byte buffer', () {
      final emptyResult = ModelVerifier.verifyModelBytes(Uint8List(0));
      expect(emptyResult.isValid, isFalse);
      expect(emptyResult.status, equals('invalid_header'));

      final shortResult = ModelVerifier.verifyModelBytes(Uint8List.fromList([1, 2, 3]));
      expect(shortResult.isValid, isFalse);
      expect(shortResult.status, equals('invalid_header'));
    });

    test('validates digital signature match', () {
      final buffer = buildMockTfliteBuffer();
      final signature = Uint8List.fromList(sha256.convert(buffer).bytes);

      final result = ModelVerifier.verifyModelBytes(
        buffer,
        signature: signature,
      );

      expect(result.isValid, isTrue);
    });

    test('fails digital signature mismatch', () {
      final buffer = buildMockTfliteBuffer();
      final wrongSignature = Uint8List.fromList([1, 2, 3, 4, 5]);

      final result = ModelVerifier.verifyModelBytes(
        buffer,
        signature: wrongSignature,
      );

      expect(result.isValid, isFalse);
      expect(result.status, equals('signature_mismatch'));
    });

    test('ensureValid throws ModelVerificationException on invalid model', () {
      final buffer = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);

      expect(
        () => ModelVerifier.ensureValid(buffer),
        throwsA(isA<ModelVerificationException>()),
      );
    });
  });

  group('GhostAI Integration with ModelVerifier', () {
    setUp(() {
      GhostAI.instance.clearCache();
    });

    test('GhostAI rejects corrupted model bytes and maintains fallback operation', () async {
      final tamperedBuffer = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x00, 0x58, 0x58, 0x58, 0x58, // "XXXX" invalid header
        0x01, 0x02, 0x03, 0x04
      ]);

      await GhostAI.instance.initializeWithBytes(tamperedBuffer);

      expect(GhostAI.instance.isModelVerified, isFalse);
      expect(GhostAI.instance.isModelLoaded, isFalse);
      expect(GhostAI.instance.verificationStatus, equals('invalid_header'));

      // Ensure prediction pipeline continues working deterministically with heuristics
      final notif = AppNotification(
        id: 'test-tampered-1',
        packageName: 'com.whatsapp',
        title: 'OTP Verification',
        content: 'Your code is 449201. Valid for 10 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);
      expect(result.reviewScore, equals(1.0)); // OTP heuristic fallback
    });

    test('GhostAI rejects checksum mismatch and maintains system boundary stability', () async {
      final validHeaderBuffer = buildMockTfliteBuffer();
      const mismatchedChecksum = 'a1b2c3d4e5f60000000000000000000000000000000000000000000000000000';

      await GhostAI.instance.initializeWithBytes(
        validHeaderBuffer,
        expectedChecksum: mismatchedChecksum,
      );

      expect(GhostAI.instance.isModelVerified, isFalse);
      expect(GhostAI.instance.isModelLoaded, isFalse);
      expect(GhostAI.instance.verificationStatus, equals('checksum_mismatch'));
    });
  });
}
