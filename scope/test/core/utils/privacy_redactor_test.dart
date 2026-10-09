import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/privacy_redactor.dart';

void main() {
  group('PrivacyRedactor Unit Tests', () {
    const redactor = PrivacyRedactor();

    test('maskOtp masks OTP codes correctly preserving prefix when length > 2', () {
      expect(redactor.maskOtp('123456'), equals('12****'));
      expect(redactor.maskOtp('987652'), equals('98****'));
      expect(redactor.maskOtp('12'), equals('**'));
      expect(redactor.maskOtp(null), isNull);
      expect(redactor.maskOtp(''), isEmpty);
    });

    test('maskAmount masks amounts correctly', () {
      expect(redactor.maskAmount(500), equals('****'));
      expect(redactor.maskAmount(500.0), equals('****'));
      expect(redactor.maskAmount('Rs. 500'), equals('Rs.****'));
      expect(redactor.maskAmount('\$100'), equals('\$****'));
      expect(redactor.maskAmount(null), isNull);
    });

    test('maskEmail masks email local part', () {
      expect(redactor.maskEmail('user@example.com'), equals('us**@example.com'));
      expect(redactor.maskEmail('ab@example.com'), equals('**@example.com'));
      expect(redactor.maskEmail(null), isNull);
    });

    test('maskPhoneNumber masks preceding digits', () {
      expect(redactor.maskPhoneNumber('+1234567890'), equals('*******7890'));
      expect(redactor.maskPhoneNumber('1234'), equals('****'));
      expect(redactor.maskPhoneNumber(null), isNull);
    });

    test('maskUrl masks path and query parameters', () {
      expect(redactor.maskUrl('https://example.com/login?token=123'), equals('https://example.com/****'));
      expect(redactor.maskUrl(null), isNull);
    });

    test('maskFeatures masks all PII fields in a map', () {
      final input = {
        'otp': '987652',
        'amount': 5000.0,
        'hasDeadline': true,
        'urls': ['https://example.com/pay'],
        'emails': ['test@example.com'],
        'phoneNumbers': ['9876543210'],
      };

      final masked = redactor.maskFeatures(input);

      expect(masked['otp'], equals('98****'));
      expect(masked['amount'], equals('****'));
      expect(masked['hasDeadline'], isTrue);
      expect(masked['urls'], equals(['https://example.com/****']));
      expect(masked['emails'], equals(['te**@example.com']));
      expect(masked['phoneNumbers'], equals(['******3210']));
    });
  });
}
