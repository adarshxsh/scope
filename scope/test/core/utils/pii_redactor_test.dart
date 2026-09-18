import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor Unit Tests', () {
    test('redactOtp masks OTP codes correctly', () {
      expect(PiiRedactor.redactOtp('123456'), equals('[REDACTED_OTP]'));
      expect(PiiRedactor.redactOtp(null), isNull);
      expect(PiiRedactor.redactOtp(''), isNull);
    });

    test('redactAmount masks monetary quantities', () {
      expect(PiiRedactor.redactAmount(5000), equals('[REDACTED_AMOUNT]'));
      expect(PiiRedactor.redactAmount('Rs. 500'), equals('[REDACTED_AMOUNT]'));
      expect(PiiRedactor.redactAmount(null), isNull);
    });

    test('redactUrl masks web hyperlinks', () {
      expect(PiiRedactor.redactUrl('https://example.com/reset'), equals('[REDACTED_URL]'));
      expect(PiiRedactor.redactUrl(['https://link1.com', 'https://link2.com']), equals('[REDACTED_URL]'));
      expect(PiiRedactor.redactUrl(null), isNull);
      expect(PiiRedactor.redactUrl([]), isNull);
    });

    test('redactEmail masks email addresses', () {
      expect(PiiRedactor.redactEmail('user@domain.org'), equals('[REDACTED_EMAIL]'));
      expect(PiiRedactor.redactEmail(null), isNull);
    });

    test('redactPhone masks phone numbers', () {
      expect(PiiRedactor.redactPhone('+19876543210'), equals('[REDACTED_PHONE]'));
      expect(PiiRedactor.redactPhone(null), isNull);
    });

    test('redactText replaces PII inside freeform text bodies', () {
      const sampleText = 'Your OTP code is 987652 for Rs. 450.00 debit. Visit https://bank.com/auth or email help@bank.com.';
      final redacted = PiiRedactor.redactText(sampleText);

      expect(redacted, contains('[REDACTED_OTP]'));
      expect(redacted, contains('[REDACTED_AMOUNT]'));
      expect(redacted, contains('[REDACTED_URL]'));
      expect(redacted, contains('[REDACTED_EMAIL]'));
      expect(redacted, isNot(contains('987652')));
      expect(redacted, isNot(contains('450.00')));
      expect(redacted, isNot(contains('https://bank.com/auth')));
      expect(redacted, isNot(contains('help@bank.com')));
    });

    test('redactMap masks sensitive extracted feature keys', () {
      final features = {
        'otp': '987652',
        'amount': 5000,
        'urls': ['https://pay.com'],
        'emails': ['alert@bank.com'],
        'phoneNumbers': ['+1234567890'],
        'hasDeadline': true,
      };

      final redacted = PiiRedactor.redactMap(features);

      expect(redacted['otp'], equals('[REDACTED_OTP]'));
      expect(redacted['amount'], equals('[REDACTED_AMOUNT]'));
      expect(redacted['urls'], equals(['[REDACTED_URL]']));
      expect(redacted['emails'], equals(['[REDACTED_EMAIL]']));
      expect(redacted['phoneNumbers'], equals(['[REDACTED_PHONE]']));
      expect(redacted['hasDeadline'], equals(true));
    });
  });
}
