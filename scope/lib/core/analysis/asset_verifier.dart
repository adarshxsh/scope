import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized verifier checking SHA-256 hashes of TFLite models, rules,
/// and vocabulary files against a pre-compiled or loaded integrity manifest.
class AssetIntegrityVerifier {
  static AssetIntegrityVerifier? _instance;

  /// Default pre-compiled asset integrity manifest containing valid SHA-256 checksums.
  static const Map<String, String> defaultManifest = {
    'model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
    'vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
    'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
    'assets/vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
  };

  Map<String, String> _manifest = Map<String, String>.from(defaultManifest);
  bool _isManifestLoaded = false;

  AssetIntegrityVerifier._();

  /// Singleton instance accessor.
  static AssetIntegrityVerifier get instance => _instance ??= AssetIntegrityVerifier._();

  /// Current manifest entries.
  Map<String, String> get manifest => Map<String, String>.unmodifiable(_manifest);

  /// Allows overriding or injecting custom manifest entries (e.g., for testing).
  void setCustomManifest(Map<String, String> manifest) {
    _manifest = Map<String, String>.from(manifest);
    _isManifestLoaded = true;
  }

  /// Resets the manifest back to the default pre-compiled manifest entries.
  void resetManifest() {
    _manifest = Map<String, String>.from(defaultManifest);
    _isManifestLoaded = false;
  }

  /// Attempts to load dynamic `assets/manifest.json` from the asset bundle if available.
  Future<void> initialize({AssetBundle? bundle}) async {
    final activeBundle = bundle ?? rootBundle;
    try {
      final jsonStr = await activeBundle.loadString('assets/manifest.json');
      final Map<String, dynamic> parsed = jsonDecode(jsonStr);
      final dynamicManifest = <String, String>{};
      parsed.forEach((key, value) {
        dynamicManifest[key] = value.toString().toLowerCase();
      });
      if (dynamicManifest.isNotEmpty) {
        _manifest.addAll(dynamicManifest);
      }
      _isManifestLoaded = true;
      debugPrint('AssetIntegrityVerifier: Manifest initialized with ${_manifest.length} entries.');
    } catch (e) {
      debugPrint('AssetIntegrityVerifier: Could not load assets/manifest.json, using compiled default manifest ($e).');
      _isManifestLoaded = true;
    }
  }

  /// Computes the SHA-256 hash of the provided byte array.
  String computeSha256(Uint8List bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Synchronously verifies raw asset bytes against the manifest for [assetName].
  bool verifyBytes(String assetName, Uint8List bytes) {
    final computedHash = computeSha256(bytes);
    final expectedHash = _lookupExpectedHash(assetName);

    if (expectedHash == null) {
      debugPrint('SECURITY WARNING [AssetIntegrityVerifier]: No manifest entry found for asset "$assetName". Rejecting asset.');
      return false;
    }

    final isValid = computedHash == expectedHash.toLowerCase();
    if (!isValid) {
      debugPrint(
        'SECURITY ALERT [AssetIntegrityVerifier]: Checksum mismatch for asset "$assetName"! '
        'Expected: $expectedHash, Computed: $computedHash. Instantiation rejected.',
      );
    } else {
      debugPrint('AssetIntegrityVerifier: Asset "$assetName" verified successfully (SHA-256: $computedHash).');
    }
    return isValid;
  }

  /// Synchronously verifies text content against the manifest for [assetName].
  bool verifyString(String assetName, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    return verifyBytes(assetName, bytes);
  }

  /// Intercepts asset loading: loads raw bytes from [assetPath], computes its SHA-256 hash,
  /// and checks against the manifest. Returns raw [Uint8List] if valid, or `null` if invalid.
  Future<Uint8List?> loadAndVerifyAsset(String assetPath, {AssetBundle? bundle}) async {
    if (!_isManifestLoaded) {
      await initialize(bundle: bundle);
    }

    try {
      final activeBundle = bundle ?? rootBundle;
      final byteData = await activeBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      if (verifyBytes(assetPath, bytes)) {
        return bytes;
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('AssetIntegrityVerifier: Failed to load asset at "$assetPath": $e');
      return null;
    }
  }

  /// Intercepts text asset loading: loads text from [assetPath], computes SHA-256 hash,
  /// and checks against the manifest. Returns UTF-8 [String] if valid, or `null` if invalid.
  Future<String?> loadAndVerifyString(String assetPath, {AssetBundle? bundle}) async {
    if (!_isManifestLoaded) {
      await initialize(bundle: bundle);
    }

    try {
      final activeBundle = bundle ?? rootBundle;
      final jsonStr = await activeBundle.loadString(assetPath);
      if (verifyString(assetPath, jsonStr)) {
        return jsonStr;
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('AssetIntegrityVerifier: Failed to load text asset at "$assetPath": $e');
      return null;
    }
  }

  String? _lookupExpectedHash(String assetName) {
    if (_manifest.containsKey(assetName)) {
      return _manifest[assetName];
    }
    // Try stripping leading path (e.g. "assets/model.tflite" -> "model.tflite")
    final filename = assetName.contains('/') ? assetName.split('/').last : assetName;
    if (_manifest.containsKey(filename)) {
      return _manifest[filename];
    }
    // Try adding "assets/" prefix
    final pathKey = 'assets/$assetName';
    if (_manifest.containsKey(pathKey)) {
      return _manifest[pathKey];
    }
    return null;
  }
}

/// Alias for AssetIntegrityVerifier.
typedef AssetVerifier = AssetIntegrityVerifier;
