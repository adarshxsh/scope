import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:scope/core/utils/pii_redactor.dart';

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from text fields.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    try {
      return json.decode(fromDb) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    final redacted = PiiRedactor.redactFeaturesMap(value);
    return json.encode(redacted);
  }
}
