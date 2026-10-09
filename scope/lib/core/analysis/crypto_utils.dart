import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pinenacl/ed25519.dart';

/// Exception thrown when cryptographic verification or payload integrity fails.
class IntegrityException implements Exception {
  final String message;

  const IntegrityException(this.message);

  @override
  String toString() => 'IntegrityException: $message';
}

/// Cryptographic utilities for Ed25519 envelope verification and HMAC-SHA256 local guards.
class CryptoUtils {
  /// Known publisher public keys keyed by key_id.
  static const String publisherKeyId = 'publisher_v1';

  /// Publisher public key (Base64 encoded 32-byte Ed25519 public key).
  static const String publisherPublicKeyBase64 = '2iJ8N+mqAEaOqHU2OhtwEcEgFjFj6c93sx0n+lzYDpk=';

  /// Default publisher private seed (Base64 encoded 32-byte seed) used for tool signing and test fixture creation.
  static const String defaultPublisherSeedBase64 =
      'BritJfSqvYJbvaXyqT9B0NjqWxpTtNB35JXzaxupIW3aInw36aoARo6odTY6G3ARwSAWMWPpz3ezHSf6XNgOmQ==';

  /// Device-secured key used for generating and verifying local HMAC-SHA256 digests.
  static const String _deviceHmacSecret = 'scope_device_secured_rlhf_hmac_key_v1';

  /// Map of registered publisher key_ids to Base64 public keys.
  static final Map<String, String> _publisherKeys = {
    publisherKeyId: publisherPublicKeyBase64,
  };

  /// Registers or overrides a publisher public key for a given [keyId].
  static void registerPublisherKey(String keyId, String publicKeyBase64) {
    _publisherKeys[keyId] = publicKeyBase64;
  }

  /// Verifies an Ed25519 signature against [messageBytes] for a given [keyId].
  ///
  /// Throws [IntegrityException] if the key_id is unknown or the signature format is invalid.
  static bool verifyEd25519Signature({
    required List<int> messageBytes,
    required String signatureBase64,
    required String keyId,
  }) {
    final pubKeyBase64 = _publisherKeys[keyId];
    if (pubKeyBase64 == null) {
      throw IntegrityException('Unknown publisher key_id: "$keyId"');
    }

    Uint8List sigBytes;
    try {
      sigBytes = Uint8List.fromList(base64.decode(signatureBase64));
    } catch (e) {
      throw IntegrityException('Invalid base64 signature format: $e');
    }

    if (sigBytes.length != 64) {
      throw IntegrityException('Ed25519 signature must be 64 bytes (got ${sigBytes.length})');
    }

    Uint8List pubBytes;
    try {
      pubBytes = Uint8List.fromList(base64.decode(pubKeyBase64));
    } catch (e) {
      throw IntegrityException('Invalid base64 public key for key_id "$keyId": $e');
    }

    try {
      final verifyKey = VerifyKey(pubBytes);
      final msg = Uint8List.fromList(messageBytes);
      return verifyKey.verify(signature: Signature(sigBytes), message: msg);
    } catch (e) {
      return false;
    }
  }

  /// Helper to sign [messageBytes] using a Base64-encoded 32-byte private seed.
  static String signEd25519({
    required List<int> messageBytes,
    String privateSeedBase64 = defaultPublisherSeedBase64,
  }) {
    final seedBytes = base64.decode(privateSeedBase64);
    final seed32 = Uint8List.fromList(seedBytes.sublist(0, 32));
    final signingKey = SigningKey.fromSeed(seed32);
    final signedMessage = signingKey.sign(Uint8List.fromList(messageBytes));
    return base64.encode(signedMessage.signature);
  }

  /// Generates an HMAC-SHA256 digest for [bytes] using the device secret.
  static String generateHmacSha256(List<int> bytes) {
    final keyBytes = utf8.encode(_deviceHmacSecret);
    final hmac = crypto.Hmac(crypto.sha256, keyBytes);
    return hmac.convert(bytes).toString();
  }

  /// Verifies [expectedHmac] against the HMAC-SHA256 digest of [bytes].
  static bool verifyHmacSha256(List<int> bytes, String expectedHmac) {
    final computed = generateHmacSha256(bytes);
    return computed == expectedHmac;
  }
}
