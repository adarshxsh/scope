import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/services/pii_redaction_service.dart';

void main() {
  group('PiiRedactionService Unit Tests', () {
    test('maskOtp masks digits except last 2 with bullets', () {
      expect(PiiRedactionService.maskOtp('882715'), equals('••••15'));
      expect(PiiRedactionService.maskOtp('352572'), equals('••••72'));
      expect(PiiRedactionService.maskOtp('1234'), equals('••34'));
      expect(PiiRedactionService.maskOtp('12'), equals('••'));
      expect(PiiRedactionService.maskOtp(null), equals('None'));
      expect(PiiRedactionService.maskOtp(''), equals('None'));
    });

    test('maskAmount formats currency with masked digits', () {
      expect(PiiRedactionService.maskAmount(5000.0), equals('₹••••.00'));
      expect(PiiRedactionService.maskAmount(249.0), equals('₹••••.00'));
      expect(PiiRedactionService.maskAmount(null), equals('None'));

      expect(PiiRedactionService.maskAmountString('Rs. 5000.0'), equals('Rs. ••••.00'));
      expect(PiiRedactionService.maskAmountString('₹249'), equals('₹••••.00'));
      expect(PiiRedactionService.maskAmountString(null), equals('None'));
    });

    test('maskEmail preserves first character and domain', () {
      expect(PiiRedactionService.maskEmail('user@domain.com'), equals('u***@domain.com'));
      expect(PiiRedactionService.maskEmail('harsh16@example.com'), equals('h***@example.com'));
      expect(PiiRedactionService.maskEmail(null), equals('None'));
      expect(PiiRedactionService.maskEmail('invalid-email'), equals('••••@••••'));
    });

    test('maskPhoneNumber masks leading digits keeping last 2', () {
      expect(PiiRedactionService.maskPhoneNumber('9876543210'), equals('••••••••10'));
      expect(PiiRedactionService.maskPhoneNumber('+91 98765 43210'), equals('••••••••10'));
      expect(PiiRedactionService.maskPhoneNumber(null), equals('None'));
    });

    test('maskUrl redacts query parameters', () {
      expect(
        PiiRedactionService.maskUrl('https://example.com/reset?token=xyz123'),
        equals('https://example.com/reset?••••'),
      );
      expect(
        PiiRedactionService.maskUrl('https://example.com/home'),
        equals('https://example.com/home'),
      );
      expect(PiiRedactionService.maskUrl(null), equals('None'));
    });

    test('redactText redacts PII in natural language strings', () {
      final input = 'Your OTP code is 882715. Amount paid is Rs. 5000. Contact user@example.com or visit https://app.com/confirm?id=102';
      final redacted = PiiRedactionService.redactText(input);

      expect(redacted, contains('••••15'));
      expect(redacted, contains('Rs. ••••.00'));
      expect(redacted, contains('u***@example.com'));
      expect(redacted, contains('https://app.com/confirm?••••'));
      expect(redacted, isNot(contains('882715')));
      expect(redacted, isNot(contains('user@example.com')));
    });
  });
}
