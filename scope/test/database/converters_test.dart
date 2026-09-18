import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('JsonConverter Unit Tests', () {
    const converter = JsonConverter();

    test('toSql encrypts JSON and prepends ENC: prefix', () {
      final features = {'otp': '123456', 'amount': 99.9};
      final sqlValue = converter.toSql(features);

      expect(sqlValue.startsWith('ENC:'), isTrue);
      expect(sqlValue, isNot(contains('123456')));
      expect(sqlValue, isNot(contains('99.9')));
    });

    test('fromSql decrypts ENC: prefixed ciphertext back to Map', () {
      final original = {'otp': '882715', 'amount': 250, 'hasDeadline': true};
      final sqlValue = converter.toSql(original);

      final restored = converter.fromSql(sqlValue);
      expect(restored['otp'], equals('882715'));
      expect(restored['amount'], equals(250));
      expect(restored['hasDeadline'], isTrue);
    });

    test('fromSql handles legacy unencrypted JSON strings', () {
      const legacyJson = '{"otp":"999111","amount":50}';
      final restored = converter.fromSql(legacyJson);

      expect(restored['otp'], equals('999111'));
      expect(restored['amount'], equals(50));
    });

    test('fromSql returns empty map on invalid or corrupt ciphertext', () {
      const corrupt = 'ENC:invalid_base64_data_###';
      final result = converter.fromSql(corrupt);

      expect(result, isEmpty);
    });
  });
}
