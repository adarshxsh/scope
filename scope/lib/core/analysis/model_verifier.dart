import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

/// Result object representing the outcome of TFLite model verification.
class ModelValidationResult {
  /// Whether all enabled validation checks (header, checksum, signature) passed.
  final bool isValid;

  /// Whether the binary header contains a valid TFLite flatbuffer magic identifier ('TFL3').
  final bool isHeaderValid;

  /// Whether the calculated SHA-256 matches the expected checksum (if provided).
  final bool isChecksumValid;

  /// Whether the digital signature / HMAC matches (if signature check was requested).
  final bool isSignatureValid;

  /// The computed SHA-256 hexadecimal hash of the model byte buffer.
  final String? sha256Hash;

  /// Human-readable explanation if validation failed.
  final String? errorReason;

  const ModelValidationResult({
    required this.isValid,
    required this.isHeaderValid,
    required this.isChecksumValid,
    required this.isSignatureValid,
    this.sha256Hash,
    this.errorReason,
  });

  /// Factory constructor for successful verification.
  factory ModelValidationResult.valid({
    required String sha256Hash,
    bool isSignatureValid = true,
  }) {
    return ModelValidationResult(
      isValid: true,
      isHeaderValid: true,
      isChecksumValid: true,
      isSignatureValid: isSignatureValid,
      sha256Hash: sha256Hash,
    );
  }

  /// Factory constructor for failed verification.
  factory ModelValidationResult.invalid({
    required String errorReason,
    bool isHeaderValid = false,
    bool isChecksumValid = false,
    bool isSignatureValid = false,
    String? sha256Hash,
  }) {
    return ModelValidationResult(
      isValid: false,
      isHeaderValid: isHeaderValid,
      isChecksumValid: isChecksumValid,
      isSignatureValid: isSignatureValid,
      sha256Hash: sha256Hash,
      errorReason: errorReason,
    );
  }

  @override
  String toString() {
    if (isValid) {
      return 'ModelValidationResult.valid(sha256: $sha256Hash)';
    }
    return 'ModelValidationResult.invalid(reason: $errorReason, header: $isHeaderValid, checksum: $isChecksumValid, signature: $isSignatureValid)';
  }
}

/// Cryptographic and binary integrity verifier for AI model assets.
class ModelVerifier {
  /// TFLite FlatBuffer magic identifier ("TFL3") at offset 4..7 in binary.
  static const List<int> tfliteMagicBytes = [0x54, 0x46, 0x4C, 0x33];

  /// Official SHA-256 checksum for the primary look-again model asset (model.tflite).
  static const String defaultModelChecksum =
      '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6';

  /// Minimum binary size required for a valid TFLite model header.
  static const int minHeaderSize = 8;

  /// Validates the TFLite flatbuffer header and magic identifier bytes ("TFL3").
  static bool validateHeader(Uint8List bytes) {
    if (bytes.length < minHeaderSize) {
      return false;
    }
    // Check magic bytes at offset 4..7
    return bytes[4] == tfliteMagicBytes[0] &&
        bytes[5] == tfliteMagicBytes[1] &&
        bytes[6] == tfliteMagicBytes[2] &&
        bytes[7] == tfliteMagicBytes[3];
  }

  /// Computes the SHA-256 hexadecimal hash string for the provided byte buffer.
  static String computeSha256(Uint8List bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Compares the calculated SHA-256 hash of [bytes] against [expectedSha256].
  static bool verifyChecksum(Uint8List bytes, String expectedSha256) {
    final calculated = computeSha256(bytes);
    return calculated == expectedSha256.trim().toLowerCase();
  }

  /// Verifies an HMAC-SHA256 signature over [bytes] using [signatureKey].
  static bool verifySignature(
    Uint8List bytes,
    List<int> expectedSignature,
    List<int> signatureKey,
  ) {
    if (expectedSignature.isEmpty || signatureKey.isEmpty) {
      return false;
    }
    final hmac = Hmac(sha256, signatureKey);
    final digest = hmac.convert(bytes);
    final calculatedBytes = digest.bytes;

    if (calculatedBytes.length != expectedSignature.length) {
      return false;
    }

    // Constant-time comparison to prevent timing attacks
    int diff = 0;
    for (int i = 0; i < calculatedBytes.length; i++) {
      diff |= calculatedBytes[i] ^ expectedSignature[i];
    }
    return diff == 0;
  }

  /// Performs full verification pipeline (header, checksum, and optional signature) on [bytes].
  static ModelValidationResult verifyBytes(
    Uint8List bytes, {
    String? expectedSha256,
    List<int>? expectedSignature,
    List<int>? signatureKey,
  }) {
    // 1. Header integrity check
    final headerValid = validateHeader(bytes);
    if (!headerValid) {
      return ModelValidationResult.invalid(
        errorReason:
            'Invalid TFLite header: buffer is truncated (< $minHeaderSize bytes) or missing magic "TFL3" identifier.',
        isHeaderValid: false,
      );
    }

    // 2. Compute cryptographic SHA-256 checksum
    final computedHash = computeSha256(bytes);

    // 3. Checksum verification
    bool checksumValid = true;
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      checksumValid = computedHash == expectedSha256.trim().toLowerCase();
      if (!checksumValid) {
        return ModelValidationResult.invalid(
          errorReason:
              'SHA-256 checksum mismatch: calculated $computedHash, expected $expectedSha256.',
          isHeaderValid: true,
          isChecksumValid: false,
          sha256Hash: computedHash,
        );
      }
    }

    // 4. Digital Signature / HMAC verification
    bool signatureValid = true;
    if (expectedSignature != null && signatureKey != null) {
      signatureValid = verifySignature(bytes, expectedSignature, signatureKey);
      if (!signatureValid) {
        return ModelValidationResult.invalid(
          errorReason: 'Digital signature / HMAC verification failed.',
          isHeaderValid: true,
          isChecksumValid: checksumValid,
          isSignatureValid: false,
          sha256Hash: computedHash,
        );
      }
    }

    return ModelValidationResult.valid(
      sha256Hash: computedHash,
      isSignatureValid: signatureValid,
    );
  }

  /// Asynchronously loads an asset from [assetPath] and verifies its integrity.
  static Future<ModelValidationResult> verifyAndLoadAsset(
    String assetPath, {
    AssetBundle? bundle,
    String? expectedSha256,
    List<int>? expectedSignature,
    List<int>? signatureKey,
  }) async {
    try {
      final actualBundle = bundle ?? rootBundle;
      final byteData = await actualBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      return verifyBytes(
        bytes,
        expectedSha256: expectedSha256,
        expectedSignature: expectedSignature,
        signatureKey: signatureKey,
      );
    } catch (e) {
      return ModelValidationResult.invalid(
        errorReason: 'Failed to load model asset "$assetPath": $e',
      );
    }
  }
}
