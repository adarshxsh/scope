import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that validates SHA-256 digests and Ed25519 digital signatures
/// of asset files against a signed manifest prior to runtime loading.
class AssetVerifierService {
  static AssetVerifierService? _instance;

  /// Default embedded release public key (Hex encoded Ed25519 public key, 32 bytes).
  static const String defaultPublicKeyHex =
      '79b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad049664';

  final Ed25519 _ed25519 = Ed25519();

  /// List of authorized Ed25519 public key hex strings to support key rotation.
  final List<String> _authorizedPublicKeys = [defaultPublicKeyHex];

  /// Cache of verified manifest entries ({assetPath: sha256Hash}).
  Map<String, String>? _verifiedManifestFiles;
  bool _isManifestSignatureVerified = false;

  /// Optional custom asset byte loader for testing or dynamic asset sources.
  Future<Uint8List?> Function(String path)? _customAssetLoader;

  AssetVerifierService._();

  /// Singleton instance accessor.
  static AssetVerifierService get instance => _instance ??= AssetVerifierService._();

  /// Sets a custom asset byte loader (primarily for testing).
  void setCustomAssetLoader(Future<Uint8List?> Function(String path)? loader) {
    _customAssetLoader = loader;
  }

  /// Adds a new public key hex string to support key rotation.
  void addAuthorizedPublicKey(String publicKeyHex) {
    final clean = publicKeyHex.trim().toLowerCase();
    if (clean.isNotEmpty && !_authorizedPublicKeys.contains(clean)) {
      _authorizedPublicKeys.add(clean);
      _logSecurity('Added authorized public key: $clean');
    }
  }

  /// Clears extra public keys and restores defaults (useful for testing).
  void resetPublicKeys() {
    _authorizedPublicKeys.clear();
    _authorizedPublicKeys.add(defaultPublicKeyHex.toLowerCase());
    clearCache();
  }

  /// Clears the cached manifest verification state.
  void clearCache() {
    _verifiedManifestFiles = null;
    _isManifestSignatureVerified = false;
  }

  /// Verifies the Ed25519 digital signature of `assets/manifest.json`.
  /// Returns `true` if signature is valid against an authorized public key.
  Future<bool> verifyManifest({
    AssetBundle? bundle,
    String? manifestJsonOverride,
  }) async {
    try {
      String jsonStr;
      if (manifestJsonOverride != null) {
        jsonStr = manifestJsonOverride;
      } else {
        Uint8List? bytes;
        if (_customAssetLoader != null) {
          bytes = await _customAssetLoader!('assets/manifest.json');
        }
        if (bytes != null) {
          jsonStr = utf8.decode(bytes);
        } else {
          final activeBundle = bundle ?? rootBundle;
          jsonStr = await activeBundle.loadString('assets/manifest.json');
        }
      }

      final Map<String, dynamic> manifestMap = jsonDecode(jsonStr) as Map<String, dynamic>;

      final String? signatureHex = manifestMap['signature'] as String?;
      if (signatureHex == null || signatureHex.trim().isEmpty) {
        _logSecurity('Manifest verification FAILED: Signature field is missing or empty.');
        return false;
      }

      final signatureBytes = _hexToBytes(signatureHex.trim());
      if (signatureBytes.length != 64) {
        _logSecurity('Manifest verification FAILED: Signature length is invalid (${signatureBytes.length} bytes, expected 64).');
        return false;
      }

      // Reconstruct canonical payload bytes (excluding signature)
      final canonicalPayloadBytes = _getCanonicalManifestPayloadBytes(manifestMap);

      bool verifiedAny = false;
      for (final pubKeyHex in _authorizedPublicKeys) {
        final pubKeyBytes = _hexToBytes(pubKeyHex);
        if (pubKeyBytes.length != 32) continue;

        final verificationSignature = Signature(
          signatureBytes,
          publicKey: SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519),
        );

        final isValid = await _ed25519.verify(
          canonicalPayloadBytes,
          signature: verificationSignature,
        );

        if (isValid) {
          verifiedAny = true;
          break;
        }
      }

      if (!verifiedAny) {
        _logSecurity('Manifest verification FAILED: Cryptographic Ed25519 signature is invalid or signed by unauthorized key.');
        _isManifestSignatureVerified = false;
        _verifiedManifestFiles = null;
        return false;
      }

      // Populate verified files map
      final filesMap = manifestMap['files'] as Map<String, dynamic>? ?? {};
      final Map<String, String> verifiedFiles = {};
      filesMap.forEach((key, value) {
        verifiedFiles[key] = value.toString().toLowerCase();
        // Also map alternate path variants (e.g. "model.tflite" vs "assets/model.tflite")
        if (key.startsWith('assets/')) {
          verifiedFiles[key.substring('assets/'.length)] = value.toString().toLowerCase();
        } else {
          verifiedFiles['assets/$key'] = value.toString().toLowerCase();
        }
      });

      _verifiedManifestFiles = verifiedFiles;
      _isManifestSignatureVerified = true;
      _logSecurity('Manifest Ed25519 digital signature successfully VERIFIED.');
      return true;
    } catch (e) {
      _logSecurity('Manifest verification EXCEPTION: $e');
      _isManifestSignatureVerified = false;
      _verifiedManifestFiles = null;
      return false;
    }
  }

  /// Verifies an asset file's cryptographic SHA-256 digest against `assets/manifest.json`.
  /// First verifies the manifest Ed25519 signature if not already verified.
  Future<bool> verifyAsset(
    String assetPath, {
    AssetBundle? bundle,
    Uint8List? customBytes,
  }) async {
    try {
      // Step 1: Verify manifest signature if not cached
      if (!_isManifestSignatureVerified || _verifiedManifestFiles == null) {
        final manifestOk = await verifyManifest(bundle: bundle);
        if (!manifestOk) {
          _logSecurity('Asset verification ABORTED for $assetPath: Manifest signature verification failed.');
          return false;
        }
      }

      // Step 2: Check expected hash in manifest
      final expectedHash = _verifiedManifestFiles![assetPath];
      if (expectedHash == null) {
        _logSecurity('Asset verification FAILED for $assetPath: Asset not registered in manifest.');
        return false;
      }

      // Step 3: Load asset bytes
      Uint8List? bytes;
      if (customBytes != null) {
        bytes = customBytes;
      } else if (_customAssetLoader != null) {
        bytes = await _customAssetLoader!(assetPath);
      }
      
      if (bytes == null) {
        final activeBundle = bundle ?? rootBundle;
        final byteData = await activeBundle.load(assetPath);
        bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      }

      if (bytes == null || bytes.isEmpty) {
        _logSecurity('Asset verification FAILED for $assetPath: Asset byte stream is empty or unreadable.');
        return false;
      }

      // Step 4: Calculate SHA-256 digest
      final calculatedDigest = sha256.convert(bytes).toString().toLowerCase();

      // Step 5: Compare digests
      if (calculatedDigest == expectedHash) {
        _logSecurity('SHA-256 verification PASSED for $assetPath (Digest: $calculatedDigest).');
        return true;
      } else {
        _logSecurity(
          'SHA-256 verification FAILED for $assetPath.\n'
          '  Expected: $expectedHash\n'
          '  Actual:   $calculatedDigest',
        );
        return false;
      }
    } catch (e) {
      _logSecurity('Asset verification EXCEPTION for $assetPath: $e');
      return false;
    }
  }

  /// Computes SHA-256 hex string for given byte buffer.
  String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Reconstructs canonical manifest payload bytes for signature verification.
  List<int> _getCanonicalManifestPayloadBytes(Map<String, dynamic> manifestMap) {
    final filesMap = manifestMap['files'] as Map<String, dynamic>? ?? {};
    final sortedFileKeys = filesMap.keys.toList()..sort();
    final Map<String, String> sortedFiles = {};
    for (final key in sortedFileKeys) {
      sortedFiles[key] = filesMap[key].toString();
    }

    final canonicalMap = <String, dynamic>{
      'files': sortedFiles,
      'version': manifestMap['version'] ?? '1.0.0',
    };

    final canonicalJsonStr = jsonEncode(canonicalMap);
    return utf8.encode(canonicalJsonStr);
  }

  List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      if (i + 2 <= clean.length) {
        final byteHex = clean.substring(i, i + 2);
        final val = int.tryParse(byteHex, radix: 16);
        if (val != null) {
          bytes.add(val);
        }
      }
    }
    return bytes;
  }

  void _logSecurity(String message) {
    debugPrint('[SECURITY] $message');
  }
}
