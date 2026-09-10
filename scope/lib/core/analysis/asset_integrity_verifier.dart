import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Status of an asset's cryptographic integrity check.
enum AssetIntegrityStatus {
  verified,
  corrupted,
  manifestMissing,
  assetMissing,
  fallback,
}

/// Detailed result of an individual asset verification check.
class AssetVerificationResult {
  final String assetPath;
  final AssetIntegrityStatus status;
  final String? expectedHash;
  final String? actualHash;
  final int? expectedLength;
  final int? actualLength;
  final int latencyMs;
  final String? errorMessage;

  const AssetVerificationResult({
    required this.assetPath,
    required this.status,
    this.expectedHash,
    this.actualHash,
    this.expectedLength,
    this.actualLength,
    required this.latencyMs,
    this.errorMessage,
  });

  bool get isVerified => status == AssetIntegrityStatus.verified;

  @override
  String toString() {
    return 'AssetVerificationResult(path: $assetPath, status: $status, latency: ${latencyMs}ms, error: $errorMessage)';
  }
}

/// Core service for loading, parsing build-time SHA-256 asset manifests
/// and performing in-memory byte hash verification prior to native model instantiation.
class AssetIntegrityVerifier {
  static AssetIntegrityVerifier? _instance;

  Map<String, Map<String, dynamic>> _manifestAssets = {};
  AssetIntegrityStatus _manifestStatus = AssetIntegrityStatus.manifestMissing;
  bool _isInitialized = false;

  final Map<String, AssetVerificationResult> _verificationResults = {};

  AssetIntegrityVerifier._();

  /// Public singleton accessor.
  static AssetIntegrityVerifier get instance => _instance ??= AssetIntegrityVerifier._();

  /// Exposes manifest initialization status.
  AssetIntegrityStatus get manifestStatus => _manifestStatus;

  /// Map of asset paths to their latest verification result.
  Map<String, AssetVerificationResult> get verificationResults =>
      Map.unmodifiable(_verificationResults);

  /// Resets internal state for unit testing.
  @visibleForTesting
  void reset() {
    _manifestAssets.clear();
    _verificationResults.clear();
    _manifestStatus = AssetIntegrityStatus.manifestMissing;
    _isInitialized = false;
  }

  /// Manually loads a manifest map for unit testing.
  @visibleForTesting
  void loadManifestFromMap(Map<String, dynamic> manifestData) {
    _manifestAssets.clear();
    final assets = manifestData['assets'];
    if (assets is Map) {
      assets.forEach((key, value) {
        if (value is Map) {
          _manifestAssets[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
      _manifestStatus = AssetIntegrityStatus.verified;
      _isInitialized = true;
    } else {
      _manifestStatus = AssetIntegrityStatus.manifestMissing;
      _isInitialized = true;
    }
  }

  /// Initializes manifest from asset bundle (defaults to rootBundle).
  Future<void> initialize({
    AssetBundle? bundle,
    String manifestPath = 'assets/asset_manifest.json',
  }) async {
    if (_isInitialized) return;

    final targetBundle = bundle ?? rootBundle;
    try {
      final jsonStr = await targetBundle.loadString(manifestPath);
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      loadManifestFromMap(decoded);
      debugPrint('[SECURITY TELEMETRY] Asset manifest loaded successfully from $manifestPath (${_manifestAssets.length} entries)');
    } catch (e) {
      _manifestStatus = AssetIntegrityStatus.manifestMissing;
      _manifestAssets.clear();
      _isInitialized = true;
      debugPrint('[SECURITY ALERT] Failed to load asset manifest at $manifestPath: $e');
    }
  }

  /// Normalizes asset path key for manifest lookups.
  String _normalizePath(String path) {
    if (path.startsWith('/')) path = path.substring(1);
    return path;
  }

  /// Finds manifest entry matching asset path (handles 'assets/foo' or 'foo').
  Map<String, dynamic>? _getManifestEntry(String assetPath) {
    final norm = _normalizePath(assetPath);
    if (_manifestAssets.containsKey(norm)) {
      return _manifestAssets[norm];
    }
    if (!norm.startsWith('assets/')) {
      final prefixed = 'assets/$norm';
      if (_manifestAssets.containsKey(prefixed)) {
        return _manifestAssets[prefixed];
      }
    } else {
      final unprefixed = norm.substring('assets/'.length);
      if (_manifestAssets.containsKey(unprefixed)) {
        return _manifestAssets[unprefixed];
      }
    }
    return null;
  }

  /// Performs in-memory SHA-256 hash and byte length check on an asset's byte array.
  AssetVerificationResult verifyBytes(String assetPath, Uint8List bytes) {
    final stopwatch = Stopwatch()..start();
    final normalizedPath = _normalizePath(assetPath);

    if (_manifestStatus == AssetIntegrityStatus.manifestMissing) {
      final result = AssetVerificationResult(
        assetPath: normalizedPath,
        status: AssetIntegrityStatus.manifestMissing,
        actualLength: bytes.length,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: 'Asset manifest file is missing or invalid',
      );
      _logTelemetry(result);
      _verificationResults[normalizedPath] = result;
      return result;
    }

    final entry = _getManifestEntry(assetPath);
    if (entry == null) {
      final result = AssetVerificationResult(
        assetPath: normalizedPath,
        status: AssetIntegrityStatus.assetMissing,
        actualLength: bytes.length,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: 'Asset path not registered in build-time manifest',
      );
      _logTelemetry(result);
      _verificationResults[normalizedPath] = result;
      return result;
    }

    final expectedHash = entry['sha256'] as String?;
    final expectedLength = entry['length'] as int?;

    final actualHash = sha256.convert(bytes).toString();
    stopwatch.stop();

    AssetIntegrityStatus status;
    String? errorMessage;

    if (expectedLength != null && bytes.length != expectedLength) {
      status = AssetIntegrityStatus.corrupted;
      errorMessage = 'Byte length mismatch (expected: $expectedLength, actual: ${bytes.length})';
    } else if (expectedHash != null && actualHash.toLowerCase() != expectedHash.toLowerCase()) {
      status = AssetIntegrityStatus.corrupted;
      errorMessage = 'SHA-256 checksum mismatch (expected: $expectedHash, actual: $actualHash)';
    } else {
      status = AssetIntegrityStatus.verified;
    }

    final result = AssetVerificationResult(
      assetPath: normalizedPath,
      status: status,
      expectedHash: expectedHash,
      actualHash: actualHash,
      expectedLength: expectedLength,
      actualLength: bytes.length,
      latencyMs: stopwatch.elapsedMilliseconds,
      errorMessage: errorMessage,
    );

    _logTelemetry(result);
    _verificationResults[normalizedPath] = result;
    return result;
  }

  /// Loads an asset from bundle and verifies its byte array against manifest.
  /// Returns the verified Uint8List bytes, or null if integrity check failed.
  Future<Uint8List?> loadAndVerifyAsset(
    String assetPath, {
    AssetBundle? bundle,
    String manifestPath = 'assets/asset_manifest.json',
  }) async {
    final targetBundle = bundle ?? rootBundle;
    await initialize(bundle: targetBundle, manifestPath: manifestPath);

    final normalizedPath = _normalizePath(assetPath);

    ByteData byteData;
    try {
      byteData = await targetBundle.load(assetPath);
    } catch (e) {
      final result = AssetVerificationResult(
        assetPath: normalizedPath,
        status: AssetIntegrityStatus.assetMissing,
        latencyMs: 0,
        errorMessage: 'Failed to load asset from bundle: $e',
      );
      _logTelemetry(result);
      _verificationResults[normalizedPath] = result;
      return null;
    }

    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    final result = verifyBytes(assetPath, bytes);
    if (result.isVerified) {
      return bytes;
    } else {
      return null;
    }
  }

  /// Queries the verification status for a given asset path.
  AssetIntegrityStatus getStatusFor(String assetPath) {
    final norm = _normalizePath(assetPath);
    final res = _verificationResults[norm];
    if (res != null) return res.status;
    if (_manifestStatus == AssetIntegrityStatus.manifestMissing) {
      return AssetIntegrityStatus.manifestMissing;
    }
    return AssetIntegrityStatus.assetMissing;
  }

  /// Outputs structured diagnostic security telemetry logs.
  void _logTelemetry(AssetVerificationResult result) {
    if (result.isVerified) {
      debugPrint('[SECURITY TELEMETRY] Asset Integrity PASSED: path=${result.assetPath}, hash=${result.actualHash}, latency=${result.latencyMs}ms');
    } else {
      debugPrint('[SECURITY ALERT] Asset Integrity FAILED: path=${result.assetPath}, status=${result.status}, expectedHash=${result.expectedHash}, actualHash=${result.actualHash}, expectedLen=${result.expectedLength}, actualLen=${result.actualLength}, error=${result.errorMessage}');
    }
  }
}
