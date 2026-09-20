import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Exception thrown when asset SHA-256 checksum verification fails.
class AssetVerificationException implements Exception {
  final String message;
  final String? assetPath;
  final String? expectedHash;
  final String? actualHash;

  AssetVerificationException(
    this.message, {
    this.assetPath,
    this.expectedHash,
    this.actualHash,
  });

  @override
  String toString() => 'AssetVerificationException: $message';
}

/// Utility module computing and validating cryptographic SHA-256 digests
/// for model, vocabulary, and rules asset buffers prior to loading.
class AssetVerifier {
  /// Predefined ground-truth SHA-256 digest constants.
  static const String modelSha256 =
      '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6';
  static const String rulesSha256 =
      '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937';
  static const String vocabSha256 =
      '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

  static const Map<String, String> _knownAssetHashes = {
    'assets/model.tflite': modelSha256,
    'assets/rules.json': rulesSha256,
    'assets/vocab.txt': vocabSha256,
    'model.tflite': modelSha256,
    'rules.json': rulesSha256,
    'vocab.txt': vocabSha256,
  };

  /// Computes the SHA-256 hexadecimal hash string for raw byte buffers in-memory.
  static String computeHash(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Verifies a raw byte buffer against an expected SHA-256 hash string.
  /// Throws an [AssetVerificationException] if verification fails.
  static bool verifyBytes(Uint8List bytes, String expectedHash, {String? assetPath}) {
    final actualHash = computeHash(bytes);
    if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
      throw AssetVerificationException(
        'SHA-256 integrity check failed for ${assetPath ?? "asset"}: '
        'expected $expectedHash, got $actualHash',
        assetPath: assetPath,
        expectedHash: expectedHash,
        actualHash: actualHash,
      );
    }
    return true;
  }

  /// Verifies asset byte buffer by looking up its expected hash constant or using [customExpectedHash].
  /// Throws [AssetVerificationException] if hash does not match or if asset is unregistered.
  static bool verifyAsset(String assetPath, Uint8List bytes, {String? customExpectedHash}) {
    final targetHash = customExpectedHash ?? _knownAssetHashes[assetPath];
    if (targetHash == null) {
      throw AssetVerificationException(
        'No registered SHA-256 hash constant for asset path: $assetPath',
        assetPath: assetPath,
      );
    }
    return verifyBytes(bytes, targetHash, assetPath: assetPath);
  }
}
