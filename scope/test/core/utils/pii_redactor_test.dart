import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor Logcat Redaction Tests', () {
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

  group('PiiRedactor UI and DB Masking Unit Tests', () {
    test('maskOtp masks OTP strings', () {
      expect(PiiRedactor.maskOtp('883102'), equals('[REDACTED OTP]'));
      expect(PiiRedactor.maskOtp(''), equals('[REDACTED OTP]'));
      expect(PiiRedactor.maskOtp(null), equals('[REDACTED OTP]'));
    });

    test('maskAmount masks currency amounts', () {
      expect(PiiRedactor.maskAmount(500.0), equals('Rs. [HIDDEN]'));
      expect(PiiRedactor.maskAmount(null), equals('Rs. [HIDDEN]'));
    });

    test('maskEmail masks email addresses', () {
      expect(PiiRedactor.maskEmail('user@example.com'), equals('[REDACTED EMAIL]'));
      expect(PiiRedactor.maskEmail(null), equals('[REDACTED EMAIL]'));
    });

    test('maskPhoneNumber masks phone numbers', () {
      expect(PiiRedactor.maskPhoneNumber('+1234567890'), equals('[REDACTED PHONE]'));
      expect(PiiRedactor.maskPhoneNumber(null), equals('[REDACTED PHONE]'));
    });

    test('maskUrl masks URLs', () {
      expect(PiiRedactor.maskUrl('https://example.com'), equals('[REDACTED URL]'));
      expect(PiiRedactor.maskUrl(null), equals('[REDACTED URL]'));
    });

    test('maskText redacts inline PII patterns from raw text snippets', () {
      const rawText =
          'Your OTP code is 987652. Debit of Rs. 5,000 on account. Contact info@bank.com or +1 800-555-0199 at https://secure.bank.com';
      final masked = PiiRedactor.maskText(rawText);

      expect(masked, contains('[REDACTED OTP]'));
      expect(masked, contains('Rs. [HIDDEN]'));
      expect(masked, contains('[REDACTED EMAIL]'));
      expect(masked, contains('[REDACTED PHONE]'));
      expect(masked, contains('[REDACTED URL]'));
      expect(masked, isNot(contains('987652')));
      expect(masked, isNot(contains('5,000')));
      expect(masked, isNot(contains('info@bank.com')));
    });

    test('redactFeaturesMap transforms PII fields in extractedFeatures map', () {
      final featuresMap = {
        'otp': '883102',
        'amount': 799.50,
        'hasDeadline': true,
        'urls': ['https://example.com/pay'],
        'emails': ['john@example.com'],
        'phoneNumbers': ['+1234567890'],
      };

      final redactedMap = PiiRedactor.redactFeaturesMap(featuresMap);

      expect(redactedMap['otp'], equals('[REDACTED OTP]'));
      expect(redactedMap['amount'], isNull);
      expect(redactedMap['hasDeadline'], isTrue);
      expect(redactedMap['urls'], equals(['[REDACTED URL]']));
      expect(redactedMap['emails'], equals(['[REDACTED EMAIL]']));
      expect(redactedMap['phoneNumbers'], equals(['[REDACTED PHONE]']));

      // Confirm in-memory original map is unmutated
      expect(featuresMap['otp'], equals('883102'));
      expect(featuresMap['amount'], equals(799.50));
    });
  });
}
