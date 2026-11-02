import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/analysis/asset_integrity_registry.dart';

/// Custom exception thrown when asset integrity validation fails.
class AssetVerificationException implements Exception {
  final String message;
  final String? assetPath;

  const AssetVerificationException(this.message, [this.assetPath]);

  @override
  String toString() =>
      'AssetVerificationException: $message${assetPath != null ? ' (asset: $assetPath)' : ''}';
}

/// Asynchronously loads asset byte streams, computes SHA-256 digests,
/// and verifies checksums against AssetIntegrityRegistry.
class AssetVerifier {
  /// Verifies an asset bundled in rootBundle against AssetIntegrityRegistry.
  /// Throws [AssetVerificationException] on hash mismatch or if un-registered.
  static Future<bool> verifyAsset(String assetPath) async {
    final expectedChecksum = AssetIntegrityRegistry.getExpectedChecksum(assetPath);
    if (expectedChecksum == null) {
      throw AssetVerificationException(
        'Asset path $assetPath is not registered in AssetIntegrityRegistry.',
        assetPath,
      );
    }

    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return verifyBytes(bytes, expectedChecksum, assetPath: assetPath);
    } catch (e) {
      if (e is AssetVerificationException) rethrow;
      throw AssetVerificationException(
        'Failed to load asset $assetPath for integrity verification: $e',
        assetPath,
      );
    }
  }

  /// Verifies raw byte array against an expected SHA-256 hex string.
  static bool verifyBytes(Uint8List bytes, String expectedSha256, {String? assetPath}) {
    final computedDigest = sha256.convert(bytes).toString().toLowerCase();
    final expectedClean = expectedSha256.trim().toLowerCase();

    if (computedDigest != expectedClean) {
      throw AssetVerificationException(
        'Integrity verification failed for $assetPath. Expected $expectedClean, computed $computedDigest.',
        assetPath,
      );
    }
    return true;
  }

  /// Verifies string content (UTF-8 bytes) against expected SHA-256 digest.
  static bool verifyString(String content, String expectedSha256, {String? assetPath}) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    return verifyBytes(bytes, expectedSha256, assetPath: assetPath);
  }
}
