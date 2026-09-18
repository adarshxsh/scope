import 'dart:convert';
import 'package:drift/drift.dart';

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
    return json.encode(value);
  }
}

/// Drift converter to serialize/deserialize `List<dynamic>` to/from text fields.
class JsonListConverter extends TypeConverter<List<dynamic>, String> {
  const JsonListConverter();

  @override
  List<dynamic> fromSql(String fromDb) {
    try {
      return json.decode(fromDb) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  @override
  String toSql(List<dynamic> value) {
    return json.encode(value);
  }
}
