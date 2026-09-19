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
    try {
      final sanitized = _sanitizeMap(value);
      return json.encode(sanitized);
    } catch (_) {
      return json.encode(value);
    }
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> input) {
    try {
      final map = Map<String, dynamic>.from(input);

      if (map.containsKey('otp') && map['otp'] != null) {
        map['otp'] = '[REDACTED_OTP]';
      }

      if (map.containsKey('amount') && map['amount'] != null) {
        map['amount'] = '[REDACTED_AMOUNT]';
      }

      if (map.containsKey('urls') && map['urls'] is Iterable) {
        map['urls'] = (map['urls'] as Iterable)
            .map((e) => e != null ? '[REDACTED_URL]' : null)
            .whereType<String>()
            .toList();
      }

      if (map.containsKey('emails') && map['emails'] is Iterable) {
        map['emails'] = (map['emails'] as Iterable)
            .map((e) => e != null ? '[REDACTED_EMAIL]' : null)
            .whereType<String>()
            .toList();
      }

      if (map.containsKey('phoneNumbers') && map['phoneNumbers'] is Iterable) {
        map['phoneNumbers'] = (map['phoneNumbers'] as Iterable)
            .map((e) => e != null ? '[REDACTED_PHONE]' : null)
            .whereType<String>()
            .toList();
      }

      return map;
    } catch (_) {
      return input;
    }
  }
}
