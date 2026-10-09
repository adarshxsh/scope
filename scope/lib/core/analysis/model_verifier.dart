import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Exception thrown when model asset verification fails checksum or header checks.
class ModelVerificationException implements Exception {
  final String message;
  final String? expectedSha256;
  final String? actualSha256;

  const ModelVerificationException(
    this.message, {
    this.expectedSha256,
    this.actualSha256,
  });

  @override
  String toString() =>
      'ModelVerificationException: $message'
      '${expectedSha256 != null ? ' (Expected: $expectedSha256, Actual: $actualSha256)' : ''}';
}

/// Cryptographic and structural verification for TensorFlow Lite model assets.
class ModelVerifier {
  ModelVerifier._();

  /// TFLite FlatBuffer magic header offset and byte representation ('TFL3')
  static const List<int> _tfliteMagicHeader = [84, 70, 76, 51]; // 'T', 'F', 'L', '3'

  /// Verifies model binary bytes for structural valid FlatBuffer headers and optional SHA-256 checksum match.
  static String verifyBytes(Uint8List bytes, {String? expectedSha256}) {
    if (bytes.isEmpty) {
      throw const ModelVerificationException('Model binary data is empty.');
    }

    if (bytes.length < 8) {
      throw ModelVerificationException(
        'Model binary length (${bytes.length} bytes) is too small to contain a valid TFLite header.',
      );
    }

    // 1. Verify FlatBuffer magic header 'TFL3' at byte offset 4..7
    final bool hasMagicHeader =
        bytes[4] == _tfliteMagicHeader[0] &&
        bytes[5] == _tfliteMagicHeader[1] &&
        bytes[6] == _tfliteMagicHeader[2] &&
        bytes[7] == _tfliteMagicHeader[3];

    if (!hasMagicHeader) {
      throw const ModelVerificationException(
        'Invalid TFLite binary header. FlatBuffer magic header "TFL3" missing at offset 4..7.',
      );
    }

    // 2. Compute SHA-256 digest
    final actualDigest = sha256.convert(bytes).toString();

    // 3. Compare SHA-256 digest if expected hash is provided
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      if (actualDigest.toLowerCase() != expectedSha256.toLowerCase()) {
        throw ModelVerificationException(
          'SHA-256 checksum mismatch.',
          expectedSha256: expectedSha256,
          actualSha256: actualDigest,
        );
      }
    }

    return actualDigest;
  }

  /// Verifies model binary file from disk.
  static Future<String> verifyFile(File file, {String? expectedSha256}) async {
    if (!await file.exists()) {
      throw ModelVerificationException(
        'Model file does not exist at path: ${file.path}',
      );
    }
    final bytes = await file.readAsBytes();
    return verifyBytes(bytes, expectedSha256: expectedSha256);
  }
}
