import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('JsonConverter Unit Tests', () {
    const converter = JsonConverter();

    test('toSql returns encrypted text prefixed with ENC:', () {
      final input = {'otp': '123456', 'amount': 500.0};
      final sql = converter.toSql(input);

      expect(sql.startsWith('ENC:'), isTrue);
      expect(sql.contains('123456'), isFalse);
      expect(sql.contains('500'), isFalse);
    });

    test('fromSql decrypts ENC: prefixed ciphertext back to Map', () {
      final input = {'otp': '987652', 'amount': 1500.0, 'isFamily': false};
      final sql = converter.toSql(input);

      final result = converter.fromSql(sql);

      expect(result['otp'], equals('987652'));
      expect(result['amount'], equals(1500.0));
      expect(result['isFamily'], isFalse);
    });

    test('fromSql decodes legacy unencrypted cleartext JSON (backwards compatibility)', () {
      const cleartextJson = '{"otp": "443322", "amount": 250.0}';

      final result = converter.fromSql(cleartextJson);

      expect(result['otp'], equals('443322'));
      expect(result['amount'], equals(250.0));
    });

    test('fromSql handles corrupted or invalid input gracefully', () {
      expect(converter.fromSql('ENC:invalidbase64!'), equals({}));
      expect(converter.fromSql('not_valid_json'), equals({}));
      expect(converter.fromSql(''), equals({}));
    });
  });
}
