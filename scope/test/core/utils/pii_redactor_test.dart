import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor', () {
    test('returns empty string for null or empty input', () {
      expect(PiiRedactor.redact(null), '');
      expect(PiiRedactor.redact(''), '');
    });

    test('redacts OTP and passcode numbers', () {
      expect(PiiRedactor.redact('Your OTP is 123456'), 'Your OTP is [REDACTED_OTP]');
      expect(PiiRedactor.redact('Use code 9876 to login'), 'Use code [REDACTED_OTP] to login');
    });

    test('redacts email addresses', () {
      expect(
        PiiRedactor.redact('Contact user@example.com for support'),
        'Contact [REDACTED_EMAIL] for support',
      );
    });

    test('redacts phone numbers', () {
      expect(
        PiiRedactor.redact('Call +1 555-123-4567 immediately'),
        'Call [REDACTED_PHONE] immediately',
      );
    });

    test('redacts monetary values', () {
      expect(
        PiiRedactor.redact(r'Your account was debited $50.00'),
        'Your account was debited [REDACTED_MONEY]',
      );
      expect(
        PiiRedactor.redact('Payment of ₹1,500 received'),
        'Payment of [REDACTED_MONEY] received',
      );
    });

    test('redacts URLs', () {
      expect(
        PiiRedactor.redact('Click here: https://security.example.com/login'),
        'Click here: [REDACTED_URL]',
      );
    });

    test('redacts Bearer tokens', () {
      expect(
        PiiRedactor.redact('Authorization: Bearer abc123xyzSecretToken'),
        'Authorization: [REDACTED_TOKEN]',
      );
    });

    test('handles clean text without sensitive PII', () {
      const cleanText = 'Meeting starting in 10 minutes';
      expect(PiiRedactor.redact(cleanText), cleanText);
    });
  });
}
