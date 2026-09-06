import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:scope/core/analysis/extracted_features.dart';

/// Drift converter to serialize/deserialize `Map<String, dynamic>` to/from text fields.
/// Applies static PII redaction tokens to sensitive entity fields during serialization and deserialization.
class JsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    try {
      final decoded = json.decode(fromDb) as Map<String, dynamic>;
      return ExtractedFeatures.redactMap(decoded) ?? decoded;
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    final sanitized = ExtractedFeatures.redactMap(value) ?? value;
    return json.encode(sanitized);
  }
}
