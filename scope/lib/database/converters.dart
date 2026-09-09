import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:scope/core/security/pii_encryption_service.dart';

/// Drift converter that encrypts/decrypts String columns using AES-256-GCM.
class EncryptedTextConverter extends TypeConverter<String, String> {
  const EncryptedTextConverter();

  @override
  String fromSql(String fromDb) {
    if (fromDb.isEmpty) return fromDb;
    return PiiEncryptionService.instance.decrypt(fromDb);
  }

  @override
  String toSql(String value) {
    if (value.isEmpty) return value;
    return PiiEncryptionService.instance.encrypt(value);
  }
}

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from AES-256-GCM encrypted text fields.
class EncryptedJsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  const EncryptedJsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return {};
    try {
      final decrypted = PiiEncryptionService.instance.decrypt(fromDb);
      return json.decode(decrypted) as Map<String, dynamic>;
    } catch (_) {
      try {
        // Fallback for unencrypted legacy JSON
        return json.decode(fromDb) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    final encoded = json.encode(value);
    return PiiEncryptionService.instance.encrypt(encoded);
  }
}

/// Drift converter alias maintained for backward compatibility.
class JsonConverter extends EncryptedJsonConverter {
  const JsonConverter();
}
