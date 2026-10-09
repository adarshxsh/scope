import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('JsonConverter Encryption Tests', () {
    const converter = JsonConverter();

    test('toSql encrypts Map and prepends ENC: prefix', () {
      final inputMap = {'otp': '123456', 'amount': 500};
      final sqlResult = converter.toSql(inputMap);

      expect(sqlResult, startsWith('ENC:'));
      expect(sqlResult, isNot(contains('123456')));
      expect(sqlResult, isNot(contains('otp')));
    });

    test('fromSql decrypts ENC: prefixed ciphertext back into Map', () {
      final originalMap = {'otp': '888999', 'amount': 1500.0, 'urls': ['https://secure.com']};
      final sqlString = converter.toSql(originalMap);

      final decryptedMap = converter.fromSql(sqlString);

      expect(decryptedMap['otp'], equals('888999'));
      expect(decryptedMap['amount'], equals(1500.0));
      expect(decryptedMap['urls'], equals(['https://secure.com']));
    });

    test('fromSql falls back to plain JSON for unencrypted legacy database entries', () {
      const legacyPlainJson = '{"otp":"555123","amount":250}';
      final parsedMap = converter.fromSql(legacyPlainJson);

      expect(parsedMap['otp'], equals('555123'));
      expect(parsedMap['amount'], equals(250));
    });

    test('fromSql handles corrupted input and invalid ciphertext gracefully returning empty map', () {
      expect(converter.fromSql('ENC:INVALID_BASE64_CIPHERTEXT'), equals({}));
      expect(converter.fromSql('INVALID_JSON_RAW_STRING'), equals({}));
      expect(converter.fromSql(''), equals({}));
    });
  });
}
