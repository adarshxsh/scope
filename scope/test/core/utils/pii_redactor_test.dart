import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor Unit Tests', () {
    test('redactEmail sanitizes emails', () {
      expect(
        PiiRedactor.redactEmail('Contact user@example.com for support'),
        equals('Contact [REDACTED EMAIL] for support'),
      );
    });

    test('redactUrl sanitizes URLs', () {
      expect(
        PiiRedactor.redactUrl('Visit https://example.com/login now'),
        equals('Visit [REDACTED URL] now'),
      );
    });

    test('redactPhone sanitizes phone numbers', () {
      expect(
        PiiRedactor.redactPhone('Call +19876543210 immediately'),
        equals('Call [REDACTED PHONE] immediately'),
      );
    });

    test('redactMonetary sanitizes currency values', () {
      expect(
        PiiRedactor.redactMonetary('Paid ₹249 for bill'),
        equals('Paid [REDACTED AMOUNT] for bill'),
      );
      expect(
        PiiRedactor.redactMonetary('Debited Rs. 500 from account'),
        equals('Debited [REDACTED AMOUNT] from account'),
      );
    });

    test('redactOtp sanitizes OTP codes', () {
      expect(
        PiiRedactor.redactOtp('Your verification code is 882715'),
        equals('Your verification code is [REDACTED OTP]'),
      );
    });

    test('redact sanitizes all PII types in text', () {
      final input = 'Paid ₹500 via https://pay.com. OTP is 123456. Email user@test.com or call 9876543210';
      final redacted = PiiRedactor.redact(input);

      expect(redacted, contains('[REDACTED AMOUNT]'));
      expect(redacted, contains('[REDACTED URL]'));
      expect(redacted, contains('[REDACTED OTP]'));
      expect(redacted, contains('[REDACTED EMAIL]'));
      expect(redacted, contains('[REDACTED PHONE]'));
    });

    test('redactFeatures sanitizes extracted features map', () {
      final features = {
        'otp': '882715',
        'amount': 249,
        'hasDeadline': true,
        'urls': ['https://example.com'],
        'emails': ['user@test.com'],
        'phoneNumbers': ['9876543210'],
      };

      final sanitized = PiiRedactor.redactFeatures(features);

      expect(sanitized['otp'], equals('[REDACTED OTP]'));
      expect(sanitized['amount'], equals('[REDACTED AMOUNT]'));
      expect(sanitized['hasDeadline'], isTrue);
      expect(sanitized['urls'], equals(['[REDACTED URL]']));
      expect(sanitized['emails'], equals(['[REDACTED EMAIL]']));
      expect(sanitized['phoneNumbers'], equals(['[REDACTED PHONE]']));
    });
  });
}
