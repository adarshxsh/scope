import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Exception thrown when asset integrity verification fails.
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

/// Helper module to validate SHA-256 digests of model, vocabulary, and rule assets
/// prior to runtime instantiation.
class AssetVerifier {
  /// Known ground-truth SHA-256 digests for core asset files.
  static const Map<String, String> expectedDigests = {
    'assets/model.tflite':
        '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/vocab.txt':
        '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
    'assets/rules.json':
        '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
  };

  /// Computes the hex-encoded SHA-256 digest of raw [bytes].
  static String computeHash(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Verifies raw [bytes] for [assetPath] against [expectedHash].
  /// If [expectedHash] is omitted, looks up [assetPath] in [expectedDigests].
  /// Throws [AssetVerificationException] if verification fails.
  static bool verifyBytes(
    Uint8List bytes,
    String assetPath, {
    String? expectedHash,
  }) {
    final expected = expectedHash ?? expectedDigests[assetPath];
    if (expected == null) {
      throw AssetVerificationException(
        'No expected digest registered for asset "$assetPath"',
        assetPath: assetPath,
      );
    }

    final actual = computeHash(bytes);
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw AssetVerificationException(
        'SHA-256 digest mismatch for asset "$assetPath": expected $expected, got $actual',
        assetPath: assetPath,
        expectedHash: expected,
        actualHash: actual,
      );
    }
    return true;
  }

  /// Loads [assetPath] from [bundle] (or [rootBundle]) and verifies its SHA-256 digest.
  /// Throws [AssetVerificationException] if verification fails.
  static Future<Uint8List> verifyAndLoadBytes(
    String assetPath, {
    AssetBundle? bundle,
    String? expectedHash,
  }) async {
    final activeBundle = bundle ?? rootBundle;
    final byteData = await activeBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    verifyBytes(bytes, assetPath, expectedHash: expectedHash);
    return bytes;
  }

  /// Verifies the SHA-256 digest for [assetPath] loaded via [bundle] or [rootBundle].
  /// Throws [AssetVerificationException] if hash verification fails.
  static Future<bool> verifyAsset(
    String assetPath, {
    AssetBundle? bundle,
    String? expectedHash,
  }) async {
    await verifyAndLoadBytes(
      assetPath,
      bundle: bundle,
      expectedHash: expectedHash,
    );
    return true;
  }

  /// Verifies SHA-256 digests for all registered core assets.
  static Future<bool> verifyAllAssets({
    AssetBundle? bundle,
    Map<String, String>? customExpectedDigests,
  }) async {
    final targets = customExpectedDigests ?? expectedDigests;
    for (final entry in targets.entries) {
      await verifyAsset(
        entry.key,
        bundle: bundle,
        expectedHash: entry.value,
      );
    }
    return true;
  }
}
