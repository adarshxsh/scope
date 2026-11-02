import 'package:flutter/foundation.dart';

/// Metadata for public keys used in rule envelope signature verification.
class PublicKeyMetadata {
  final String keyId;
  final String algorithm;
  final String publicKey;
  final bool active;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const PublicKeyMetadata({
    required this.keyId,
    required this.algorithm,
    required this.publicKey,
    this.active = true,
    this.createdAt,
    this.expiresAt,
  });

  /// Returns whether this key is valid at the current time.
  bool isValid([DateTime? time]) {
    if (!active) return false;
    final now = time ?? DateTime.now();
    if (createdAt != null && now.isBefore(createdAt!)) return false;
    if (expiresAt != null && now.isAfter(expiresAt!)) return false;
    return true;
  }
}

/// Registry of embedded public verification keys with key rotation support.
class EmbeddedKeys {
  static final Map<String, PublicKeyMetadata> _keys = {
    // Official root key for static rule database assets (RSA-2048)
    'scope-root-key-1': PublicKeyMetadata(
      keyId: 'scope-root-key-1',
      algorithm: 'RSA-SHA256',
      publicKey:
          'a3e4b48adb7dcf64c02ef92cd17b09d3ba09b38c4f0f8718cbbbbb93bd420376'
          '702b89cdd55adc77d6324736d546d88778ff86563e8d1c6d09ce6938a9b45b29'
          '7039b5caedc1ce5772dff6bb6a10b9da103a04587a47a58d2a67b3cd4a1c1eb9'
          '4e4548072f8f62a961e78191522b368da42e8a0d63743768dc7ba737f8d0069a'
          '8a2812b4439470f3fad40355d2e282629a65bef87d3590052688635db41dc6f9'
          'f88b19bb69f4970482ef12e5e6d6121f5eeead0e21da111d49335b6991493a3e'
          'f4e4978b8abd5dce81f2c13c353dbc48a36b47c82f682c72990409993c8b47b8'
          'c1961995d03ac23012d1e97ddab5e09ac04d75d40fbe07efde0107e01c4e59f5',
      active: true,
      createdAt: DateTime(2025, 1, 1),
      expiresAt: DateTime(2035, 1, 1),
    ),

    // Secondary Ed25519 root key
    'scope-root-key-ed25519': PublicKeyMetadata(
      keyId: 'scope-root-key-ed25519',
      algorithm: 'Ed25519',
      publicKey:
          'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      active: true,
      createdAt: DateTime(2025, 1, 1),
      expiresAt: DateTime(2035, 1, 1),
    ),

    // Device local key guardrail for user custom RLHF rules
    'scope-rlhf-local-key': const PublicKeyMetadata(
      keyId: 'scope-rlhf-local-key',
      algorithm: 'HMAC-SHA256',
      publicKey: 'scope-device-local-rlhf-guardrail-secret-2026',
      active: true,
    ),

    // Revoked key used for testing key rotation / revocation
    'scope-revoked-key-0': PublicKeyMetadata(
      keyId: 'scope-revoked-key-0',
      algorithm: 'RSA-SHA256',
      publicKey: '00112233445566778899aabbccddeeff',
      active: false,
      createdAt: DateTime(2020, 1, 1),
      expiresAt: DateTime(2024, 1, 1),
    ),
  };

  /// Retrieves a public key by ID, verifying active status and expiration.
  static PublicKeyMetadata? getKey(String keyId) {
    final key = _keys[keyId];
    if (key == null) {
      debugPrint('EmbeddedKeys: Key ID "$keyId" not found.');
      return null;
    }
    if (!key.isValid()) {
      debugPrint('EmbeddedKeys: Key ID "$keyId" is inactive or expired.');
      return null;
    }
    return key;
  }

  /// Registers or updates a key dynamically (useful for tests or key rotation).
  static void registerKey(PublicKeyMetadata metadata) {
    _keys[metadata.keyId] = metadata;
  }
}
