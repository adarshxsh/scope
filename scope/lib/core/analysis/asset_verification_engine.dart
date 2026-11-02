import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents the verification status of a single asset.
enum AssetVerificationStatus {
  unverified,
  verified,
  failed,
}

/// Cryptographic Asset Verification Engine enforcing SHA-256 integrity
/// verification for model and configuration assets prior to memory loading.
class AssetVerificationEngine {
  static AssetVerificationEngine? _instance;

  static const Map<String, String> defaultManifest = {
    'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
    'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
  };

  final Map<String, String> _manifest = Map<String, String>.from(defaultManifest);
  final Map<String, AssetVerificationStatus> _statusMap = {};
  final Map<String, String> _computedHashes = {};

  AssetVerificationEngine._();

  static AssetVerificationEngine get instance => _instance ??= AssetVerificationEngine._();

  /// Gets the currently expected SHA-256 manifest.
  Map<String, String> get manifest => Map.unmodifiable(_manifest);

  /// Gets verification statuses for assets.
  Map<String, AssetVerificationStatus> get verificationStatuses => Map.unmodifiable(_statusMap);

  /// Gets computed SHA-256 hashes for assets that have been processed.
  Map<String, String> get computedHashes => Map.unmodifiable(_computedHashes);

  /// Set/override expected hash for an asset path (useful for testing tampered assets).
  void setExpectedHash(String assetPath, String expectedSha256) {
    _manifest[assetPath] = expectedSha256.toLowerCase();
    _statusMap[assetPath] = AssetVerificationStatus.unverified;
  }

  /// Reset manifest to original default signed manifest.
  void resetManifest() {
    _manifest.clear();
    _manifest.addAll(defaultManifest);
    _statusMap.clear();
    _computedHashes.clear();
  }

  /// Loads asset bytes from bundle, verifies SHA-256 checksum against signed manifest,
  /// and returns verified bytes if integrity check passes.
  /// Returns `null` if verification fails or asset cannot be loaded.
  Future<Uint8List?> loadAndVerifyByteData(
    String assetPath, {
    AssetBundle? bundle,
  }) async {
    final activeBundle = bundle ?? rootBundle;
    try {
      final ByteData byteData = await activeBundle.load(assetPath);
      final Uint8List bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final String computedHash = sha256.convert(bytes).toString().toLowerCase();
      _computedHashes[assetPath] = computedHash;

      final String? expectedHash = _manifest[assetPath]?.toLowerCase();

      if (expectedHash != null && computedHash == expectedHash) {
        _statusMap[assetPath] = AssetVerificationStatus.verified;
        debugPrint(
          'AssetVerificationEngine: Verified asset "$assetPath" [SHA256: ${computedHash.substring(0, 8)}...]',
        );
        return bytes;
      } else {
        _statusMap[assetPath] = AssetVerificationStatus.failed;
        debugPrint(
          'AssetVerificationEngine: SECURITY FAILURE - Asset "$assetPath" SHA-256 mismatch! '
          'Expected: $expectedHash, Computed: $computedHash',
        );
        return null;
      }
    } catch (e) {
      _statusMap[assetPath] = AssetVerificationStatus.failed;
      debugPrint('AssetVerificationEngine: Error loading asset "$assetPath": $e');
      return null;
    }
  }

  /// Loads asset text string from bundle after performing SHA-256 integrity verification.
  /// Returns `null` if verification fails or asset cannot be loaded.
  Future<String?> loadAndVerifyString(
    String assetPath, {
    AssetBundle? bundle,
  }) async {
    final Uint8List? bytes = await loadAndVerifyByteData(assetPath, bundle: bundle);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (e) {
      debugPrint('AssetVerificationEngine: Failed to decode text asset "$assetPath": $e');
      return null;
    }
  }

  /// Verifies all registered manifest assets.
  Future<Map<String, bool>> verifyAllAssets({AssetBundle? bundle}) async {
    final Map<String, bool> results = {};
    for (final assetPath in _manifest.keys) {
      final bytes = await loadAndVerifyByteData(assetPath, bundle: bundle);
      results[assetPath] = bytes != null;
    }
    return results;
  }

  /// Returns whether a specific asset is verified.
  bool isAssetVerified(String assetPath) {
    return _statusMap[assetPath] == AssetVerificationStatus.verified;
  }
}
