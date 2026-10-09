import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart';

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from text fields using AES-256 encryption.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonConverter();

  static final Key _key = Key.fromUtf8('scope_pii_encryption_key_32bytes');
  static final IV _iv = IV.fromUtf8('scope_pii_iv_16b');
  static final Encrypter _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return {};
    try {
      if (fromDb.startsWith('ENC:')) {
        final cipherText = fromDb.substring(4);
        final decryptedStr = _encrypter.decrypt(Encrypted.fromBase64(cipherText), iv: _iv);
        return json.decode(decryptedStr) as Map<String, dynamic>;
      } else {
        return json.decode(fromDb) as Map<String, dynamic>;
      }
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    try {
      final rawJson = json.encode(value);
      final encrypted = _encrypter.encrypt(rawJson, iv: _iv);
      return 'ENC:${encrypted.base64}';
    } catch (_) {
      return 'ENC:';
    }
  }
}
