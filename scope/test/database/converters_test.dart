import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('JsonConverter AES Encryption Tests', () {
    const converter = JsonConverter();

    test('Encrypts Map into AES ciphertext (starts with ENC: prefix)', () {
      final input = {
        'otp': '987652',
        'amount': 500,
        'hasDeadline': false,
        'emails': ['test@example.com'],
      };

      final sqlValue = converter.toSql(input);

      // Verify sqlValue is encrypted ciphertext, not plaintext JSON
      expect(sqlValue.startsWith('ENC:'), isTrue);
      expect(sqlValue.contains('987652'), isFalse);
      expect(sqlValue.contains('test@example.com'), isFalse);
    });

    test('Decrypts encrypted ciphertext back into Map<String, dynamic>', () {
      final input = {
        'otp': '123456',
        'amount': '1000',
        'urls': ['https://secret.com/verify'],
      };

      final sqlValue = converter.toSql(input);
      final decoded = converter.fromSql(sqlValue);

      expect(decoded, equals(input));
      expect(decoded['otp'], equals('123456'));
      expect(decoded['urls'], equals(['https://secret.com/verify']));
    });

    test('Fallback: correctly decodes unencrypted legacy JSON strings', () {
      const legacyJson = '{"otp":"999888","amount":250,"hasDeadline":true}';

      final decoded = converter.fromSql(legacyJson);

      expect(decoded['otp'], equals('999888'));
      expect(decoded['amount'], equals(250));
      expect(decoded['hasDeadline'], isTrue);
    });

    test('Returns empty map when given invalid/corrupted ciphertext or JSON', () {
      expect(converter.fromSql('ENC:invalid:corrupted'), equals({}));
      expect(converter.fromSql('not_valid_json'), equals({}));
    });
  });
}
