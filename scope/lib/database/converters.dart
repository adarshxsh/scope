import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from encrypted text fields using AES-256.
class EncryptedJsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  static final encrypt.Key _key = encrypt.Key.fromUtf8(
    'ScopeAES256SecretKeyForDriftDB!'.padRight(32).substring(0, 32),
  );
  static final encrypt.IV _iv = encrypt.IV.fromUtf8(
    'ScopeAES256IV123'.padRight(16).substring(0, 16),
  );
  static final encrypt.Encrypter _encrypter = encrypt.Encrypter(
    encrypt.AES(_key, mode: encrypt.AESMode.cbc),
  );

  static const String _prefix = 'enc:';

  const EncryptedJsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return {};
    try {
      String rawJson;
      if (fromDb.startsWith(_prefix)) {
        final cipherText = fromDb.substring(_prefix.length);
        rawJson = _encrypter.decrypt(encrypt.Encrypted.fromBase64(cipherText), iv: _iv);
      } else {
        try {
          rawJson = _encrypter.decrypt(encrypt.Encrypted.fromBase64(fromDb), iv: _iv);
        } catch (_) {
          rawJson = fromDb;
        }
      }
      return json.decode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      try {
        return json.decode(fromDb) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    final rawJson = json.encode(value);
    final encrypted = _encrypter.encrypt(rawJson, iv: _iv);
    return '$_prefix${encrypted.base64}';
  }
}

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from text fields with AES-256 encryption.
class JsonConverter extends EncryptedJsonConverter {
  const JsonConverter();
}

