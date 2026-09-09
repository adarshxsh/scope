import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/security/pii_redactor.dart';

void main() {
  group('PiiRedactor Unit Tests', () {
    test('maskOtp masks digits correctly preserving last 2 digits', () {
      expect(PiiRedactor.maskOtp('882715'), equals('****15'));
      expect(PiiRedactor.maskOtp('1234'), equals('**34'));
      expect(PiiRedactor.maskOtp('34'), equals('**'));
      expect(PiiRedactor.maskOtp(null), equals('None'));
    });

    test('maskAmount formats transaction amounts correctly', () {
      expect(PiiRedactor.maskAmount('5000'), equals('\$***.00'));
      expect(PiiRedactor.maskAmount('Rs. 5,000'), equals('Rs. ***0'));
      expect(PiiRedactor.maskAmount('₹799'), equals('₹***9'));
      expect(PiiRedactor.maskAmount(null), equals('None'));
    });

    test('maskUrl masks scheme and domain info', () {
      expect(PiiRedactor.maskUrl('https://example.com/login?token=abc'), equals('https://***'));
      expect(PiiRedactor.maskUrl('http://test.org'), equals('http://***'));
      expect(PiiRedactor.maskUrl(null), equals('None'));
    });

    test('maskEmail masks username and domain name', () {
      expect(PiiRedactor.maskEmail('harsh16@example.com'), equals('h*****6@example.com'));
      expect(PiiRedactor.maskEmail('user@test.org'), equals('u**r@test.org'));
      expect(PiiRedactor.maskEmail(null), equals('None'));
    });

    test('maskPhoneNumber masks phone digits preserving last 4', () {
      expect(PiiRedactor.maskPhoneNumber('+1 555-123-4567'), equals('***-***-4567'));
      expect(PiiRedactor.maskPhoneNumber('9876543210'), equals('******3210'));
      expect(PiiRedactor.maskPhoneNumber(null), equals('None'));
    });

    test('redactText replaces PII occurrences in string', () {
      const rawText = 'Contact user@domain.com or call +1 555-123-4567 at https://secure.bank.com';
      final redacted = PiiRedactor.redactText(rawText);

      expect(redacted, isNot(contains('user@domain.com')));
      expect(redacted, isNot(contains('555-123-4567')));
      expect(redacted, isNot(contains('secure.bank.com')));
      expect(redacted, contains('@domain.com'));
      expect(redacted, contains('4567'));
      expect(redacted, contains('https://***'));
    });
  });
}
