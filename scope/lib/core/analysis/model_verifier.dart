import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Utility class responsible for loading asset manifests and verifying cryptographic SHA-256 checksums
/// of ML model binaries and configuration assets prior to runtime instantiation.
class ModelVerifier {
  static ModelVerifier? _instance;
  static ModelVerifier get instance => _instance ??= ModelVerifier._();

  Map<String, String>? _manifestCache;
  static const String defaultManifestPath = 'assets/asset_manifest.json';

  ModelVerifier._();

  /// Creates a separate instance for testing or standalone usage.
  factory ModelVerifier.create() => ModelVerifier._();

  /// Loads and parses the asset manifest JSON if not already cached.
  Future<bool> loadManifest({String manifestPath = defaultManifestPath}) async {
    if (_manifestCache != null) return true;

    try {
      final jsonStr = await rootBundle.loadString(manifestPath);
      final dynamic decoded = jsonDecode(jsonStr);

      if (decoded is Map<String, dynamic>) {
        final Map<String, String> manifest = {};
        decoded.forEach((key, value) {
          if (value is String) {
            manifest[key] = value;
          }
        });
        _manifestCache = manifest;
        return true;
      } else {
        debugPrint('ModelVerifier: Integrity Error: Manifest at $manifestPath is not a valid JSON map.');
        return false;
      }
    } catch (e) {
      debugPrint('ModelVerifier: Integrity Error: Failed to load manifest at $manifestPath: $e');
      return false;
    }
  }

  /// Verifies an asset's SHA-256 checksum against the loaded manifest.
  /// Returns `true` if valid, or `false` if verification fails.
  Future<bool> verify(String path, {Uint8List? bytes}) async {
    try {
      if (_manifestCache == null) {
        final loaded = await loadManifest();
        if (!loaded || _manifestCache == null) {
          debugPrint('ModelVerifier: Integrity Error: Manifest unavailable for asset verification: "$path"');
          return false;
        }
      }

      final expectedDigest = _getExpectedDigest(path);
      if (expectedDigest == null) {
        debugPrint('ModelVerifier: Integrity Error: No manifest digest found for asset "$path"');
        return false;
      }

      final Uint8List assetBytes;
      if (bytes != null) {
        assetBytes = bytes;
      } else {
        final byteData = await rootBundle.load(path);
        assetBytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      }

      final actualDigest = sha256.convert(assetBytes).toString();
      final isValid = actualDigest.toLowerCase() == expectedDigest.toLowerCase();

      if (!isValid) {
        debugPrint(
          'ModelVerifier: Integrity Error: SHA-256 digest mismatch for "$path". '
          'Expected: $expectedDigest, Actual: $actualDigest',
        );
      } else {
        debugPrint('ModelVerifier: Asset "$path" verified successfully (SHA-256: $actualDigest).');
      }

      return isValid;
    } catch (e) {
      debugPrint('ModelVerifier: Integrity Error: Exception while verifying asset "$path": $e');
      return false;
    }
  }

  /// Convenience static method forwarding to the default instance `verify`.
  static Future<bool> verifyAsset(String path, {Uint8List? bytes}) {
    return instance.verify(path, bytes: bytes);
  }

  /// Verifies and loads raw bytes for an asset. Returns `null` if verification fails.
  Future<Uint8List?> verifyAndLoadBytes(String path) async {
    try {
      final byteData = await rootBundle.load(path);
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      final isValid = await verify(path, bytes: bytes);
      return isValid ? bytes : null;
    } catch (e) {
      debugPrint('ModelVerifier: Integrity Error: Failed to load bytes for "$path": $e');
      return null;
    }
  }

  /// Verifies and loads text content for an asset. Returns `null` if verification fails.
  Future<String?> verifyAndLoadString(String path) async {
    final bytes = await verifyAndLoadBytes(path);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (e) {
      debugPrint('ModelVerifier: Integrity Error: Failed to decode string asset "$path": $e');
      return null;
    }
  }

  /// Helper to lookup expected digest handling path variants (`assets/name` vs `name`).
  String? _getExpectedDigest(String path) {
    if (_manifestCache == null) return null;
    if (_manifestCache!.containsKey(path)) return _manifestCache![path];

    if (path.startsWith('assets/')) {
      final withoutAssets = path.substring(7);
      if (_manifestCache!.containsKey(withoutAssets)) return _manifestCache![withoutAssets];
    } else {
      final withAssets = 'assets/$path';
      if (_manifestCache!.containsKey(withAssets)) return _manifestCache![withAssets];
    }

    return null;
  }

  /// Sets manifest map directly (useful for testing).
  void setManifestForTesting(Map<String, String>? manifest) {
    _manifestCache = manifest != null ? Map.from(manifest) : null;
  }

  /// Clears in-memory manifest cache (useful for testing).
  void resetCache() {
    _manifestCache = null;
  }
}
