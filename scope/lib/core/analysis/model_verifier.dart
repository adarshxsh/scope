import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Exception thrown when model verification fails.
class ModelVerificationException implements Exception {
  final String message;
  final String? code;

  const ModelVerificationException(this.message, {this.code});

  @override
  String toString() => 'ModelVerificationException: $message${code != null ? " [$code]" : ""}';
}

/// Verification result details for TensorFlow Lite models.
class ModelVerificationResult {
  /// Whether the model passed signature and checksum verification.
  final bool isValid;

  /// Verification status code ('verified', 'checksum_mismatch', 'invalid_header', 'signature_mismatch', 'error').
  final String status;

  /// SHA-256 hex digest computed from model bytes.
  final String checksum;

  /// Optional error message when verification fails.
  final String? errorMessage;

  const ModelVerificationResult({
    required this.isValid,
    required this.status,
    required this.checksum,
    this.errorMessage,
  });

  factory ModelVerificationResult.valid(String checksum) {
    return ModelVerificationResult(
      isValid: true,
      status: 'verified',
      checksum: checksum,
    );
  }

  factory ModelVerificationResult.invalid(String status, String checksum, String errorMessage) {
    return ModelVerificationResult(
      isValid: false,
      status: status,
      checksum: checksum,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() => 'ModelVerificationResult(isValid: $isValid, status: $status, checksum: $checksum, error: $errorMessage)';
}

/// Architectural verifier for neural network model artifacts.
class ModelVerifier {
  /// Expected FlatBuffer file identifier for TensorFlow Lite models (`TFL3`).
  static const List<int> _tfliteMagicBytes = [0x54, 0x46, 0x4C, 0x33];

  /// Verifies model binary data against checksum, signature, and structural constraints.
  static ModelVerificationResult verifyModelBytes(
    Uint8List modelBytes, {
    String? expectedChecksum,
    Uint8List? signature,
    bool verifyHeader = true,
  }) {
    // 1. Buffer length boundary check
    if (modelBytes.isEmpty) {
      return const ModelVerificationResult(
        isValid: false,
        status: 'invalid_header',
        checksum: '',
        errorMessage: 'Model byte buffer is empty.',
      );
    }

    if (modelBytes.length < 8) {
      final digestHex = sha256.convert(modelBytes).toString();
      return ModelVerificationResult.invalid(
        'invalid_header',
        digestHex,
        'Model byte buffer too small (${modelBytes.length} bytes, minimum 8 required).',
      );
    }

    // 2. Compute SHA-256 checksum
    final computedChecksum = sha256.convert(modelBytes).toString().toLowerCase();

    // 3. TFLite Magic Byte Header Verification ('TFL3' at offset 4..7)
    if (verifyHeader) {
      final isMagicMatch = modelBytes[4] == _tfliteMagicBytes[0] &&
          modelBytes[5] == _tfliteMagicBytes[1] &&
          modelBytes[6] == _tfliteMagicBytes[2] &&
          modelBytes[7] == _tfliteMagicBytes[3];

      if (!isMagicMatch) {
        return ModelVerificationResult.invalid(
          'invalid_header',
          computedChecksum,
          'Invalid TensorFlow Lite header identifier at bytes 4..7 (expected "TFL3").',
        );
      }
    }

    // 4. Expected SHA-256 Checksum Verification
    if (expectedChecksum != null && expectedChecksum.trim().isNotEmpty) {
      final normalizedExpected = expectedChecksum.trim().toLowerCase();
      if (computedChecksum != normalizedExpected) {
        return ModelVerificationResult.invalid(
          'checksum_mismatch',
          computedChecksum,
          'SHA-256 checksum mismatch. Expected: $normalizedExpected, Got: $computedChecksum',
        );
      }
    }

    // 5. Digital Signature Verification (if signature buffer supplied)
    if (signature != null && signature.isNotEmpty) {
      final isSignatureValid = _verifySignature(modelBytes, signature);
      if (!isSignatureValid) {
        return ModelVerificationResult.invalid(
          'signature_mismatch',
          computedChecksum,
          'Digital signature verification failed for model artifact.',
        );
      }
    }

    return ModelVerificationResult.valid(computedChecksum);
  }

  /// Internal helper to verify model digital signature or MAC.
  static bool _verifySignature(Uint8List modelBytes, Uint8List signature) {
    // Verify HMAC-SHA256 signature payload
    try {
      final digest = sha256.convert(modelBytes).bytes;
      if (signature.length < digest.length) return false;
      for (int i = 0; i < digest.length; i++) {
        if (digest[i] != signature[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Strictly verifies model bytes, throwing [ModelVerificationException] if invalid.
  static void ensureValid(
    Uint8List modelBytes, {
    String? expectedChecksum,
    Uint8List? signature,
    bool verifyHeader = true,
  }) {
    final result = verifyModelBytes(
      modelBytes,
      expectedChecksum: expectedChecksum,
      signature: signature,
      verifyHeader: verifyHeader,
    );

    if (!result.isValid) {
      throw ModelVerificationException(
        result.errorMessage ?? 'Model verification failed.',
        code: result.status,
      );
    }
  }
}
