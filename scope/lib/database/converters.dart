import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart';

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from text fields with AES-256 encryption.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  static final Key _key = Key.fromUtf8('12345678901234567890123456789012');
  static final IV _iv = IV.fromUtf8('16bytes_scope_iv');
  static final Encrypter _encrypter = Encrypter(AES(_key, mode: AESMode.cbc, padding: 'PKCS7'));

  const JsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    try {
      if (fromDb.startsWith('ENC:')) {
        final cipherText = fromDb.substring(4);
        final decrypted = _encrypter.decrypt64(cipherText, iv: _iv);
        return json.decode(decrypted) as Map<String, dynamic>;
      }
      return json.decode(fromDb) as Map<String, dynamic>;
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
      return json.encode(value);
    }
  }
}
