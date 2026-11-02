import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor Tests', () {
    test('redact handles null and empty inputs gracefully', () {
      expect(PiiRedactor.redact(null), equals(''));
      expect(PiiRedactor.redact(''), equals(''));
      expect(PiiRedactor.redactTitle(null), equals(''));
      expect(PiiRedactor.redactContent(''), equals(''));
    });

    test('redact leaves clean non-sensitive text untouched', () {
      const text = 'Meeting starts in 15 minutes in Room 302.';
      expect(PiiRedactor.redact(text), equals(text));
    });

    test('redact sanitizes OTPs and passcodes', () {
      const input = 'Your verification code is 882715. Valid for 10 minutes.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_OTP]'));
      expect(redacted, isNot(contains('882715')));
    });

    test('redact sanitizes credit card numbers', () {
      const input = 'Card 4532-1100-8890-2311 authorized.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_CARD]'));
      expect(redacted, isNot(contains('4532-1100-8890-2311')));
    });

    test('redact sanitizes email addresses', () {
      const input = 'Security alert for user.name@domain.co.in from new device.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_EMAIL]'));
      expect(redacted, isNot(contains('user.name@domain.co.in')));
    });

    test('redact sanitizes URLs and web links', () {
      const input = 'Click https://example.com/reset?token=12345 to reset password.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_URL]'));
      expect(redacted, isNot(contains('https://example.com/reset?token=12345')));
    });

    test('redact sanitizes monetary amounts', () {
      const input1 = r'Your account was debited $150.50 on March 12.';
      const input2 = 'Received payment of Rs. 5,000 via UPI.';
      expect(PiiRedactor.redact(input1), contains('[REDACTED_AMOUNT]'));
      expect(PiiRedactor.redact(input2), contains('[REDACTED_AMOUNT]'));
    });

    test('redact sanitizes phone numbers', () {
      const input = 'Call customer support at 800-555-0199 for assistance.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_PHONE]'));
      expect(redacted, isNot(contains('800-555-0199')));
    });

    test('redact handles multiple sensitive entities in a single notification string', () {
      const input = r'OTP 998811 for payment of $250.00 to user@pay.com';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_OTP]'));
      expect(redacted, contains('[REDACTED_AMOUNT]'));
      expect(redacted, contains('[REDACTED_EMAIL]'));
      expect(redacted, isNot(contains('998811')));
      expect(redacted, isNot(contains(r'$250.00')));
      expect(redacted, isNot(contains('user@pay.com')));
    });
  });

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

      expect(redacted, contains('[REDACTED_AMOUNT]'));
      expect(redacted, contains('[REDACTED_URL]'));
      expect(redacted, contains('[REDACTED_OTP]'));
      expect(redacted, contains('[REDACTED_EMAIL]'));
      expect(redacted, contains('[REDACTED_PHONE]'));
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
