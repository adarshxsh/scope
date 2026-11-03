import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('EncryptedJsonConverter Unit Tests', () {
    late EncryptedJsonConverter converter;

    setUp(() {
      converter = const EncryptedJsonConverter();
    });

    test('toSql encrypts Map into AES-256 base64 ciphertext with enc: prefix', () {
      final input = {
        'otp': '882715',
        'amount': 5000.0,
        'hasDeadline': true,
        'emails': ['user@example.com'],
        'phoneNumbers': ['9876543210'],
      };

      final sqlValue = converter.toSql(input);

      // Verify that plain text values are NOT present in the SQL output
      expect(sqlValue, startsWith('enc:'));
      expect(sqlValue, isNot(contains('882715')));
      expect(sqlValue, isNot(contains('user@example.com')));
      expect(sqlValue, isNot(contains('9876543210')));
      expect(sqlValue, isNot(contains('5000')));
    });

    test('fromSql decrypts ciphertext back into original Map', () {
      final originalMap = {
        'otp': '882715',
        'amount': 5000.0,
        'hasDeadline': true,
        'emails': ['user@example.com'],
      };

      final sqlValue = converter.toSql(originalMap);
      final restoredMap = converter.fromSql(sqlValue);

      expect(restoredMap['otp'], equals('882715'));
      expect(restoredMap['amount'], equals(5000.0));
      expect(restoredMap['hasDeadline'], isTrue);
      expect(restoredMap['emails'], equals(['user@example.com']));
    });

    test('fromSql falls back gracefully to legacy unencrypted JSON', () {
      final legacyRawJson = '{"otp":"123456","amount":100.0}';
      final restoredMap = converter.fromSql(legacyRawJson);

      expect(restoredMap['otp'], equals('123456'));
      expect(restoredMap['amount'], equals(100.0));
    });

    test('fromSql returns empty map for empty/invalid string', () {
      expect(converter.fromSql(''), equals({}));
      expect(converter.fromSql('invalid-string'), equals({}));
    });
  });
}
