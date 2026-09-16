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

/// Drift converter to serialize/deserialize `List<double>` to/from text fields.
class JsonListConverter extends TypeConverter<List<double>, String> {
  const JsonListConverter();

  @override
  List<double> fromSql(String fromDb) {
    try {
      final decoded = json.decode(fromDb) as List;
      return decoded.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  String toSql(List<double> value) {
    return json.encode(value);
  }
}

