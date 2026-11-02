import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from encrypted text fields.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  static const String prefix = 'ENC:';

  // Standard 256-bit (32 byte) key for local symmetric key encryption
  static final encrypt.Key _defaultKey = encrypt.Key.fromUtf8('scope_privacy_db_key_32_bytes!!!');

  const JsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return {};

    try {
      if (fromDb.startsWith(prefix)) {
        final rawCipher = fromDb.substring(prefix.length);
        final decoded = base64.decode(rawCipher);

        if (decoded.length < 16) return {};

        final ivBytes = decoded.sublist(0, 16);
        final cipherBytes = decoded.sublist(16);

        final encrypter = encrypt.Encrypter(encrypt.AES(_defaultKey, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
        final decrypted = encrypter.decrypt(
          encrypt.Encrypted(Uint8List.fromList(cipherBytes)),
          iv: encrypt.IV(Uint8List.fromList(ivBytes)),
        );

        return json.decode(decrypted) as Map<String, dynamic>;
      } else {
        // Legacy unencrypted cleartext JSON fallback
        return json.decode(fromDb) as Map<String, dynamic>;
      }
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    try {
      final jsonStr = json.encode(value);
      encrypt.IV iv;
      try {
        iv = encrypt.IV.fromSecureRandom(16);
      } catch (_) {
        iv = encrypt.IV.fromLength(16);
      }
      final encrypter = encrypt.Encrypter(encrypt.AES(_defaultKey, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(jsonStr, iv: iv);

      final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
      combined.setAll(0, iv.bytes);
      combined.setAll(iv.bytes.length, encrypted.bytes);

      return '$prefix${base64.encode(combined)}';
    } catch (_) {
      return json.encode(value);
    }
  }
}

