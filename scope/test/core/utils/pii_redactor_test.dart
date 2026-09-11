import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
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
