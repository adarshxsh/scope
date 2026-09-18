import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Exception thrown when asset SHA-256 verification fails.
class AssetVerificationException implements Exception {
  final String message;
  const AssetVerificationException(this.message);

  @override
  String toString() => 'AssetVerificationException: $message';
}

/// Utility for computing and verifying cryptographic SHA-256 digests of runtime assets.
class AssetVerifier {
  /// Known asset SHA-256 digests.
  static const Map<String, String> expectedHashes = {
    'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
    'assets/vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
  };

  /// Computes SHA-256 hex digest for a byte stream/buffer.
  static String computeHash(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Verifies byte buffer against an explicit SHA-256 hex string.
  static bool verifyHash(Uint8List bytes, String expectedHash) {
    final actualHash = computeHash(bytes);
    return actualHash.toLowerCase() == expectedHash.toLowerCase();
  }

  /// Verifies byte buffer against registered SHA-256 digest for assetPath.
  static bool verifyAsset(String assetPath, Uint8List bytes) {
    final expected = expectedHashes[assetPath];
    if (expected == null) {
      debugPrint('AssetVerifier: No registered SHA-256 hash for asset $assetPath');
      return false;
    }
    final actualHash = computeHash(bytes);
    final matches = actualHash.toLowerCase() == expected.toLowerCase();
    if (!matches) {
      debugPrint(
        'AssetVerifier: SHA-256 checksum mismatch for $assetPath. Expected: $expected, Actual: $actualHash',
      );
    }
    return matches;
  }

  /// Verifies asset byte buffer and returns it, or throws [AssetVerificationException] on mismatch.
  static Uint8List verifyAndGetBuffer(String assetPath, Uint8List bytes) {
    if (!verifyAsset(assetPath, bytes)) {
      final actual = computeHash(bytes);
      final expected = expectedHashes[assetPath] ?? 'unknown';
      throw AssetVerificationException(
        'SHA-256 checksum mismatch for asset "$assetPath". Expected: $expected, Actual: $actual',
      );
    }
    return bytes;
  }
}
