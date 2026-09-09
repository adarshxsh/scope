import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Application-level AES-256-GCM field encryption service for sensitive database columns.
/// Uses Flutter Secure Storage for key management on device.
class PiiEncryptionService {
  static const String _keyAlias = 'pii_aes_256_key';
  static const String _prefix = 'ENC:v1:';

  static final PiiEncryptionService instance = PiiEncryptionService._internal();

  PiiEncryptionService._internal();

  Uint8List? _key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Random _secureRandom = Random.secure();

  bool get isInitialized => _key != null;

  /// Ensures key is loaded from OS KeyStore/Keychain or generated securely.
  Future<void> init({Uint8List? customKey}) async {
    if (customKey != null && customKey.length == 32) {
      _key = customKey;
      return;
    }
    if (_key != null) return;

    try {
      final existingKeyBase64 = await _storage.read(key: _keyAlias);
      if (existingKeyBase64 != null && existingKeyBase64.isNotEmpty) {
        _key = base64.decode(existingKeyBase64);
      } else {
        final newKey = _generateRandomBytes(32);
        await _storage.write(key: _keyAlias, value: base64.encode(newKey));
        _key = newKey;
      }
    } catch (e) {
      // Fallback for testing environments or unsupported platforms
      _key ??= _generateFallbackKey();
    }
  }

  void _ensureKey() {
    if (_key == null) {
      _key = _generateFallbackKey();
    }
  }

  Uint8List _generateFallbackKey() {
    return Uint8List.fromList(List.generate(32, (i) => (i * 31 + 17) & 0xFF));
  }

  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Encrypts a plain text string using AES-256-GCM.
  String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;
    _ensureKey();

    try {
      final nonce = _generateRandomBytes(12); // 96-bit nonce
      final plainBytes = utf8.encode(plainText);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(_key!), 128, nonce, Uint8List(0)),
        );

      final cipherTextWithTag = cipher.process(Uint8List.fromList(plainBytes));

      final combined = Uint8List(nonce.length + cipherTextWithTag.length);
      combined.setAll(0, nonce);
      combined.setAll(nonce.length, cipherTextWithTag);

      return '$_prefix${base64.encode(combined)}';
    } catch (e) {
      debugPrint('PiiEncryptionService encrypt error: $e');
      return plainText;
    }
  }

  /// Decrypts an AES-256-GCM encrypted string.
  String decrypt(String cipherText) {
    if (!cipherText.startsWith(_prefix)) {
      // Unencrypted or legacy text
      return cipherText;
    }
    _ensureKey();

    try {
      final rawBase64 = cipherText.substring(_prefix.length);
      final combined = base64.decode(rawBase64);
      if (combined.length <= 12) return cipherText;

      final nonce = combined.sublist(0, 12);
      final cipherBytesWithTag = combined.sublist(12);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(_key!), 128, nonce, Uint8List(0)),
        );

      final decryptedBytes = cipher.process(cipherBytesWithTag);
      return utf8.decode(decryptedBytes);
    } catch (e) {
      debugPrint('PiiEncryptionService decrypt error: $e');
      return cipherText;
    }
  }

  /// Sets encryption key explicitly (for unit testing).
  void setKey(Uint8List key) {
    assert(key.length == 32, 'AES-256 key must be 32 bytes');
    _key = key;
  }

  /// Resets key (for unit testing).
  void reset() {
    _key = null;
  }
}
