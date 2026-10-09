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
    test('redactOtp masks OTP codes while preserving optional last digits', () {
      expect(PiiRedactor.redactOtp('987652'), equals('••••52'));
      expect(PiiRedactor.redactOtp('1234'), equals('••34'));
      expect(PiiRedactor.redactOtp('12'), equals('••••'));
      expect(PiiRedactor.redactOtp(null), equals('None'));
    });

    test('redactAmount masks monetary values and amounts', () {
      expect(PiiRedactor.redactAmount(500), equals('Rs. ••••'));
      expect(PiiRedactor.redactAmount('Rs. 1500'), equals('Rs. ••••'));
      expect(PiiRedactor.redactAmount('\$250'), equals('\$••••'));
      expect(PiiRedactor.redactAmount(null), equals('None'));
    });

    test('redactEmail masks email addresses', () {
      expect(PiiRedactor.redactEmail('john.doe@example.com'), equals('j•••••••@e••••••.com'));
      expect(PiiRedactor.redactEmail('a@b.com'), equals('a•••@b•••.com'));
      expect(PiiRedactor.redactEmail(null), equals('None'));
    });

    test('redactPhoneNumber masks digits in phone numbers', () {
      expect(PiiRedactor.redactPhoneNumber('+1234567890'), equals('+••••••7890'));
      expect(PiiRedactor.redactPhoneNumber('9876543210'), equals('••••••3210'));
      expect(PiiRedactor.redactPhoneNumber(null), equals('None'));
    });

    test('redactUrl masks domain and path in URLs', () {
      expect(PiiRedactor.redactUrl('https://example.com/secret/token'), equals('https://••••'));
      expect(PiiRedactor.redactUrl('http://mybank.com/login'), equals('http://••••'));
      expect(PiiRedactor.redactUrl(null), equals('None'));
    });

    test('redactDefiningWord masks post-mortem trace chip labels', () {
      expect(PiiRedactor.redactDefiningWord('OTP:987652'), equals('OTP:••••'));
      expect(PiiRedactor.redactDefiningWord('Amount:Rs.500'), equals('Amount:Rs.••••'));
      expect(PiiRedactor.redactDefiningWord('sbi'), equals('sbi'));
      expect(PiiRedactor.redactDefiningWord('debited'), equals('debited'));
    });
  });
}
