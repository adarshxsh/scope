import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Exception thrown when asset verification fails due to digest mismatch or missing hash configuration.
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Utility class for verifying SHA-256 digests of assets prior to loading.
class AssetVerifier {
  /// Immutable compile-time constants for expected SHA-256 asset digests.
  static const String modelSha256 = '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6';
  static const String rulesSha256 = '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937';
  static const String vocabSha256 = '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

  /// Lookup table mapping asset paths to expected SHA-256 digest constants.
  static const Map<String, String> expectedHashes = {
    'assets/model.tflite': modelSha256,
    'assets/rules.json': rulesSha256,
    'assets/vocab.txt': vocabSha256,
  };

  AssetVerifier._();

  /// Loads an asset from rootBundle, computes its SHA-256 digest, and compares
  /// it against the expected hash constant.
  /// Returns the raw asset byte buffer ([Uint8List]) if verification succeeds.
  /// Throws a [SecurityException] if the asset path is unconfigured or the hash mismatches.
  static Future<Uint8List> loadAndVerify(String assetPath) async {
    final expectedHash = expectedHashes[assetPath];
    if (expectedHash == null) {
      throw SecurityException('No expected SHA-256 hash registered for asset path: $assetPath');
    }

    final ByteData byteData = await rootBundle.load(assetPath);
    final Uint8List bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    if (!verifyBytes(bytes, expectedHash)) {
      final computedHash = computeSha256(bytes);
      throw SecurityException(
        'Asset verification failed for $assetPath. Expected $expectedHash but got $computedHash.',
      );
    }

    return bytes;
  }

  /// Computes the SHA-256 hex string digest for raw byte buffer.
  static String computeSha256(Uint8List bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Verifies raw byte buffer against an expected SHA-256 hex string.
  static bool verifyBytes(Uint8List bytes, String expectedHash) {
    final computedHash = computeSha256(bytes);
    return computedHash == expectedHash.toLowerCase();
  }
}
