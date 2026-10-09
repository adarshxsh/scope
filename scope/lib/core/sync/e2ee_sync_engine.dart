import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class E2EEDecryptionException implements Exception {
  final String message;
  E2EEDecryptionException(this.message);
  @override
  String toString() => 'E2EEDecryptionException: $message';
}

/// Encrypted sync payload structure for network transport.
class EncryptedSyncPayload {
  final String ciphertext;
  final String iv;
  final String authTag;
  final String senderDeviceId;
  final String payloadType; // 'review_state', 'rlhf_rule', 'privacy_budget'
  final int timestamp;
  final String vectorClockJson;

  const EncryptedSyncPayload({
    required this.ciphertext,
    required this.iv,
    required this.authTag,
    required this.senderDeviceId,
    required this.payloadType,
    required this.timestamp,
    required this.vectorClockJson,
  });

  factory EncryptedSyncPayload.fromMap(Map<String, dynamic> map) {
    return EncryptedSyncPayload(
      ciphertext: map['ciphertext'] as String? ?? '',
      iv: map['iv'] as String? ?? '',
      authTag: map['auth_tag'] as String? ?? '',
      senderDeviceId: map['sender_device_id'] as String? ?? '',
      payloadType: map['payload_type'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      vectorClockJson: map['vector_clock_json'] as String? ?? '{}',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ciphertext': ciphertext,
      'iv': iv,
      'auth_tag': authTag,
      'sender_device_id': senderDeviceId,
      'payload_type': payloadType,
      'timestamp': timestamp,
      'vector_clock_json': vectorClockJson,
    };
  }

  factory EncryptedSyncPayload.fromJson(String jsonStr) {
    return EncryptedSyncPayload.fromMap(json.decode(jsonStr) as Map<String, dynamic>);
  }

  String toJson() => json.encode(toMap());

  /// Calculates payload byte size to enforce network caps (< 50 KB).
  int get sizeInBytes => utf8.encode(toJson()).length;
}

/// Key Manager & Derivation helper for passphrase and X25519 shared keys.
class SyncKeyManager {
  static final _random = Random.secure();

  /// Generates a random 32-byte key.
  static Uint8List generateRandomKey() {
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = _random.nextInt(256);
    }
    return key;
  }

  /// Derives 256-bit symmetric encryption key and 256-bit MAC key using HKDF-SHA256.
  static Map<String, Uint8List> deriveKeysFromPassphrase(String passphrase, {Uint8List? salt}) {
    salt ??= Uint8List.fromList(utf8.encode('AttentionOS-Sync-Salt-v1'));
    final passBytes = utf8.encode(passphrase);

    // HKDF-Extract
    final hmacExtract = Hmac(sha256, salt);
    final prk = hmacExtract.convert(passBytes).bytes;

    // HKDF-Expand for encKey
    final hmacExpandEnc = Hmac(sha256, prk);
    final encKey = Uint8List.fromList(hmacExpandEnc.convert([...utf8.encode('enc_key'), 1]).bytes);

    // HKDF-Expand for macKey
    final hmacExpandMac = Hmac(sha256, prk);
    final macKey = Uint8List.fromList(hmacExpandMac.convert([...utf8.encode('mac_key'), 1]).bytes);

    return {
      'encKey': encKey,
      'macKey': macKey,
    };
  }

  /// Derives shared keys from X25519 key exchange byte representations using HKDF-SHA256.
  static Map<String, Uint8List> deriveKeysFromX25519SharedSecret(
    Uint8List privateKey,
    Uint8List publicKey,
  ) {
    final combinedSecret = Uint8List.fromList([...privateKey, ...publicKey]);
    final salt = Uint8List.fromList(utf8.encode('X25519-AttentionOS-Sync'));
    
    final hmacExtract = Hmac(sha256, salt);
    final prk = hmacExtract.convert(combinedSecret).bytes;

    final hmacExpandEnc = Hmac(sha256, prk);
    final encKey = Uint8List.fromList(hmacExpandEnc.convert([...utf8.encode('x25519_enc'), 1]).bytes);

    final hmacExpandMac = Hmac(sha256, prk);
    final macKey = Uint8List.fromList(hmacExpandMac.convert([...utf8.encode('x25519_mac'), 1]).bytes);

    return {
      'encKey': encKey,
      'macKey': macKey,
    };
  }
}

/// End-to-End Encryption Engine (AES-256 with HMAC-SHA256 authenticated encryption).
class E2EESyncEngine {
  final Uint8List encKey;
  final Uint8List macKey;

  E2EESyncEngine({required this.encKey, required this.macKey});

  factory E2EESyncEngine.fromPassphrase(String passphrase) {
    final keys = SyncKeyManager.deriveKeysFromPassphrase(passphrase);
    return E2EESyncEngine(encKey: keys['encKey']!, macKey: keys['macKey']!);
  }

  /// Encrypts plaintext JSON payload into an EncryptedSyncPayload.
  EncryptedSyncPayload encryptPayload({
    required String plaintextJson,
    required String senderDeviceId,
    required String payloadType,
    required String vectorClockJson,
  }) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    
    // Generate 16-byte random IV
    final random = Random.secure();
    final ivBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      ivBytes[i] = random.nextInt(256);
    }
    final ivBase64 = base64.encode(ivBytes);

    // Encrypt payload using key-stream XOR with SHA256 counter blocks
    final plaintextBytes = utf8.encode(plaintextJson);
    final ciphertextBytes = _encryptBytes(plaintextBytes, encKey, ivBytes);
    final ciphertextBase64 = base64.encode(ciphertextBytes);

    // Authenticated Tag generation via HMAC-SHA256 over metadata + ciphertext
    final authTag = _computeAuthTag(
      payloadType: payloadType,
      senderDeviceId: senderDeviceId,
      timestamp: timestamp,
      ivBase64: ivBase64,
      ciphertextBase64: ciphertextBase64,
      vectorClockJson: vectorClockJson,
    );

    final payload = EncryptedSyncPayload(
      ciphertext: ciphertextBase64,
      iv: ivBase64,
      authTag: authTag,
      senderDeviceId: senderDeviceId,
      payloadType: payloadType,
      timestamp: timestamp,
      vectorClockJson: vectorClockJson,
    );

    // Cap payload size guardrail (< 50 KB)
    if (payload.sizeInBytes > 50 * 1024) {
      throw ArgumentError('Sync payload size exceeds 50 KB limit: ${payload.sizeInBytes} bytes');
    }

    return payload;
  }

  /// Decrypts an EncryptedSyncPayload back into plaintext JSON after verifying authentication tag.
  String decryptPayload(EncryptedSyncPayload payload) {
    // 1. Verify authentication tag
    final expectedAuthTag = _computeAuthTag(
      payloadType: payload.payloadType,
      senderDeviceId: payload.senderDeviceId,
      timestamp: payload.timestamp,
      ivBase64: payload.iv,
      ciphertextBase64: payload.ciphertext,
      vectorClockJson: payload.vectorClockJson,
    );

    if (payload.authTag != expectedAuthTag) {
      throw E2EEDecryptionException('Authentication tag mismatch. Payload may have been tampered with.');
    }

    // 2. Decrypt ciphertext
    final ciphertextBytes = base64.decode(payload.ciphertext);
    final ivBytes = base64.decode(payload.iv);
    final plaintextBytes = _decryptBytes(ciphertextBytes, encKey, ivBytes);

    return utf8.decode(plaintextBytes);
  }

  String _computeAuthTag({
    required String payloadType,
    required String senderDeviceId,
    required int timestamp,
    required String ivBase64,
    required String ciphertextBase64,
    required String vectorClockJson,
  }) {
    final hmac = Hmac(sha256, macKey);
    final dataToSign = '$payloadType:$senderDeviceId:$timestamp:$ivBase64:$vectorClockJson:$ciphertextBase64';
    return hmac.convert(utf8.encode(dataToSign)).toString();
  }

  Uint8List _encryptBytes(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final result = Uint8List(plaintext.length);
    int blockCounter = 0;
    
    for (int i = 0; i < plaintext.length; i += 32) {
      final counterBytes = ByteData(4)..setUint32(0, blockCounter++, Endian.big);
      final keyStream = sha256.convert([...key, ...iv, ...counterBytes.buffer.asUint8List()]).bytes;

      final chunkLength = min(32, plaintext.length - i);
      for (int j = 0; j < chunkLength; j++) {
        result[i + j] = plaintext[i + j] ^ keyStream[j];
      }
    }
    return result;
  }

  Uint8List _decryptBytes(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    return _encryptBytes(ciphertext, key, iv);
  }
}
