import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart';

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from encrypted text fields.
/// 
/// Employs AES-256 encryption with PKCS7 padding and prepends an `ENC:` header to serialized ciphertext,
/// maintaining backward compatibility with legacy unencrypted JSON strings.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  static const String _encPrefix = 'ENC:';

  static final Key _defaultKey = Key(
    Uint8List.fromList(
      sha256.convert(utf8.encode('scope_extracted_features_sec_key_v1')).bytes,
    ),
  );

  final Key? customKey;

  const JsonConverter([this.customKey]);

  Key get _effectiveKey => customKey ?? _defaultKey;

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    try {
      if (fromDb.startsWith(_encPrefix)) {
        final cipherPayload = fromDb.substring(_encPrefix.length);
        final combinedBytes = base64.decode(cipherPayload);
        if (combinedBytes.length <= 16) {
          return {};
        }

        final ivBytes = combinedBytes.sublist(0, 16);
        final encBytes = combinedBytes.sublist(16);

        final iv = IV(ivBytes);
        final encrypted = Encrypted(encBytes);
        final encrypter = Encrypter(AES(_effectiveKey, mode: AESMode.cbc, padding: 'PKCS7'));

        final decryptedStr = encrypter.decrypt(encrypted, iv: iv);
        return json.decode(decryptedStr) as Map<String, dynamic>;
      }

      // Legacy fallback for plain text JSON payload
      return json.decode(fromDb) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    try {
      final jsonStr = json.encode(value);
      final iv = IV.fromSecureRandom(16);
      final encrypter = Encrypter(AES(_effectiveKey, mode: AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(jsonStr, iv: iv);

      final combinedBytes = Uint8List(16 + encrypted.bytes.length);
      combinedBytes.setAll(0, iv.bytes);
      combinedBytes.setAll(16, encrypted.bytes);

      final encodedStr = base64.encode(combinedBytes);
      return '$_encPrefix$encodedStr';
    } catch (_) {
      return json.encode(value);
    }
  }
}
