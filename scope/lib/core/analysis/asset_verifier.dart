import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Asset verifier component calculating SHA-256 digests of loaded buffers
/// and comparing them against the asset manifest before model/rule loading.
class AssetVerifier {
  static const String manifestPath = 'assets/asset_manifest.json';

  /// Computes the hex SHA-256 digest of a byte buffer.
  static String computeSha256(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Loads and parses the asset manifest from the specified bundle or rootBundle.
  static Future<Map<String, String>> loadManifest([AssetBundle? bundle]) async {
    final effectiveBundle = bundle ?? rootBundle;
    try {
      final jsonString = await effectiveBundle.loadString(manifestPath);
      final Map<String, dynamic> rawMap = json.decode(jsonString);
      return rawMap.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Validates a byte buffer against the asset manifest for the given [assetPath].
  /// Returns `true` if the computed digest matches the manifest hash, `false` otherwise.
  static bool verifyBuffer(
    List<int> bytes,
    String assetPath, {
    Map<String, String>? manifest,
  }) {
    if (bytes.isEmpty) return false;
    if (manifest == null || manifest.isEmpty) return false;

    final computedHash = computeSha256(bytes).toLowerCase();

    final expectedHash = manifest[assetPath] ??
        manifest[assetPath.replaceFirst('assets/', '')] ??
        manifest['assets/$assetPath'];

    if (expectedHash == null) return false;

    return computedHash == expectedHash.toLowerCase();
  }

  /// Convenience method to load manifest and verify buffer in one step.
  static Future<bool> verifyAssetBuffer(
    List<int> bytes,
    String assetPath, {
    AssetBundle? bundle,
  }) async {
    final manifest = await loadManifest(bundle);
    return verifyBuffer(bytes, assetPath, manifest: manifest);
  }
}
