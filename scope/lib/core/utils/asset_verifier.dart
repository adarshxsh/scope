import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Exception thrown when asset cryptographic SHA-256 verification fails.
class AssetVerificationException implements Exception {
  final String message;
  AssetVerificationException(this.message);

  @override
  String toString() => 'AssetVerificationException: $message';
}

/// Utility class for calculating SHA-256 asset checksums and verifying integrity
/// before loading model assets, vocab files, and rules into memory.
class AssetVerifier {
  /// Pre-configured trusted SHA-256 checksums for core assets.
  static const Map<String, String> trustedChecksums = {
    'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
    'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
  };

  /// Computes the SHA-256 checksum string (lowercase hex format) for a raw byte array.
  static String computeSha256(Uint8List bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Verifies if a raw byte array matches an expected SHA-256 checksum string.
  static bool verifyBytes(Uint8List bytes, String expectedHash) {
    final computed = computeSha256(bytes);
    return computed == expectedHash.toLowerCase();
  }

  /// Loads raw byte data for an asset at [assetPath] from Flutter [rootBundle] (or custom [bundle]),
  /// calculates its SHA-256 checksum, and compares it against [expectedHash]
  /// (or pre-configured trusted checksum if [expectedHash] is null).
  ///
  /// Returns the raw [Uint8List] bytes upon successful verification.
  /// Throws [AssetVerificationException] if verification fails.
  static Future<Uint8List> loadAndVerifyAsset(
    String assetPath, {
    String? expectedHash,
    AssetBundle? bundle,
  }) async {
    final targetBundle = bundle ?? rootBundle;
    final ByteData data = await targetBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final expected = expectedHash ?? trustedChecksums[assetPath];
    if (expected != null) {
      final actualHash = computeSha256(bytes);
      if (actualHash != expected.toLowerCase()) {
        throw AssetVerificationException(
          'Checksum mismatch for asset "$assetPath". Expected: $expected, Actual: $actualHash',
        );
      }
    }

    return bytes;
  }
}
