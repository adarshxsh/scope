import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor Unit Tests', () {
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
