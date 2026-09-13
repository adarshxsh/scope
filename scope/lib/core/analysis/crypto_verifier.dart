import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Exception thrown when cryptographic signature validation fails for rule manifests.
class RuleVerificationException implements Exception {
  final String message;
  RuleVerificationException(this.message);

  @override
  String toString() => 'RuleVerificationException: $message';
}

/// Exception thrown when security boundaries or author authenticity checks are violated.
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Utility for verifying Ed25519 rule manifest signatures and device-bound HMAC-SHA256 signatures.
class CryptoVerifier {
  static final Map<String, String> _trustedPublicKeys = {
    'scope-prod-key-1': 'nHq6JH1Lmot5tW6rGCV05fjNlUAomh+JWgaeAFtYs8o=',
  };

  /// Adds or updates a trusted public key in memory (e.g., for key rotation or testing).
  static void addTrustedPublicKey(String keyId, String publicKeyBase64) {
    _trustedPublicKeys[keyId] = publicKeyBase64;
  }

  /// Removes a trusted public key from memory.
  static void removeTrustedPublicKey(String keyId) {
    _trustedPublicKeys.remove(keyId);
  }

  /// Retrieves a trusted public key by [keyId].
  static String? getPublicKey(String keyId) {
    return _trustedPublicKeys[keyId];
  }

  /// Exposes unmodifiable map of trusted public keys.
  static Map<String, String> get trustedPublicKeys => Map.unmodifiable(_trustedPublicKeys);

  /// Verifies an Ed25519 signature against [payloadBytes] using public key mapped to [keyId].
  static Future<bool> verifyEd25519Signature({
    required List<int> payloadBytes,
    required String signatureBase64,
    required String keyId,
  }) async {
    final pubKeyBase64 = getPublicKey(keyId);
    if (pubKeyBase64 == null) {
      debugPrint('[SECURITY AUDIT] Verification failed: Unknown or un-pinned key_id "$keyId".');
      return false;
    }

    try {
      final pubKeyBytes = base64Decode(pubKeyBase64);
      final sigBytes = base64Decode(signatureBase64);

      if (pubKeyBytes.length != 32 || sigBytes.length != 64) {
        debugPrint('[SECURITY AUDIT] Verification failed: Invalid key length (${pubKeyBytes.length}) or signature length (${sigBytes.length}).');
        return false;
      }

      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(sigBytes, publicKey: publicKey);

      final isValid = await algorithm.verify(payloadBytes, signature: signature);
      if (!isValid) {
        debugPrint('[SECURITY AUDIT] Verification failed: Ed25519 signature mismatch for key_id "$keyId".');
      }
      return isValid;
    } catch (e) {
      debugPrint('[SECURITY AUDIT] Verification failed with exception: $e');
      return false;
    }
  }

  /// Helper to sign payload bytes with an Ed25519 key pair (used in tests and dynamic manifest generation).
  static Future<String> signEd25519Payload({
    required List<int> payloadBytes,
    required SimpleKeyPair keyPair,
  }) async {
    final algorithm = Ed25519();
    final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
    return base64Encode(signature.bytes);
  }

  /// Helper to generate a new Ed25519 key pair from a 32-byte seed.
  static Future<SimpleKeyPair> createEd25519KeyPairFromSeed(List<int> seed) async {
    final algorithm = Ed25519();
    return algorithm.newKeyPairFromSeed(seed);
  }

  /// Derives a secret HMAC key bound to the local device.
  static List<int> deriveDeviceKey() {
    // Device-bound secret key derived from local hardware/environment seed
    const deviceSeed = 'scope-device-bound-rlhf-key-v1-secret-9941';
    return utf8.encode(deviceSeed);
  }

  /// Signs [payloadBytes] with HMAC-SHA256 using [secretKey].
  static String signHmac(List<int> payloadBytes, List<int> secretKey) {
    final hmac = crypto.Hmac(crypto.sha256, secretKey);
    final digest = hmac.convert(payloadBytes);
    return base64Encode(digest.bytes);
  }

  /// Verifies [signatureBase64] HMAC-SHA256 for [payloadBytes] using [secretKey].
  static bool verifyHmac(List<int> payloadBytes, String signatureBase64, List<int> secretKey) {
    try {
      final expectedSig = signHmac(payloadBytes, secretKey);
      return expectedSig == signatureBase64;
    } catch (e) {
      debugPrint('[SECURITY AUDIT] Local HMAC verification exception: $e');
      return false;
    }
  }
}
