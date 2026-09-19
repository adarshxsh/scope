import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Drift converter to encrypt/decrypt `Map<String, dynamic>` to/from text fields using AES-256.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonConverter();

  // 256-bit default key for AES encryption (32 bytes)
  static encrypt.Key _key = encrypt.Key.fromUtf8('ScopeAppAES256SecretKey32Bytes!!');

  /// Allows setting a custom encryption key (e.g., loaded from secure storage).
  static void setKey(Uint8List keyBytes) {
    if (keyBytes.length == 32) {
      _key = encrypt.Key(keyBytes);
    }
  }

  static encrypt.Encrypter get _encrypter =>
      encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    try {
      if (fromDb.startsWith('ENC:')) {
        final parts = fromDb.split(':');
        if (parts.length == 3) {
          final iv = encrypt.IV.fromBase64(parts[1]);
          final encrypted = encrypt.Encrypted.fromBase64(parts[2]);
          final decrypted = _encrypter.decrypt(encrypted, iv: iv);
          return json.decode(decrypted) as Map<String, dynamic>;
        }
      }
      // Fallback for unencrypted legacy JSON data
      return json.decode(fromDb) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    try {
      final jsonString = json.encode(value);
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(jsonString, iv: iv);
      return 'ENC:${iv.base64}:${encrypted.base64}';
    } catch (_) {
      return json.encode(value);
    }
  }
}

