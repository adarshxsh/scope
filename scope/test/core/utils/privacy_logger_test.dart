import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/privacy_logger.dart';

void main() {
  group('PrivacyLogger PII Masking Tests', () {
    test('masks OTP codes correctly', () {
      final input = 'Your verification code is 882715. Valid for 10 minutes.';
      final masked = PrivacyLogger.maskPII(input);
      expect(masked, contains('[OTP]'));
      expect(masked, isNot(contains('882715')));
    });

    test('masks email addresses correctly', () {
      final input = 'Contact support at john.doe@example.com for assistance.';
      final masked = PrivacyLogger.maskPII(input);
      expect(masked, contains('[EMAIL]'));
      expect(masked, isNot(contains('john.doe@example.com')));
    });

    test('masks phone numbers correctly', () {
      final input = 'Call +1-555-123-4567 or 555-987-6543 immediately.';
      final masked = PrivacyLogger.maskPII(input);
      expect(masked, contains('[PHONE]'));
      expect(masked, isNot(contains('555-123-4567')));
    });

    test('masks financial transaction amounts correctly', () {
      final input = r'Account debited by $150.00 or ₹5,000 or Rs 500.';
      final masked = PrivacyLogger.maskPII(input);
      expect(masked, contains('[AMOUNT]'));
      expect(masked, isNot(contains('150.00')));
    });

    test('safeSummary truncates and masks PII', () {
      final input = 'OTP 123456 for confidential account access';
      final summary = PrivacyLogger.safeSummary(input, maxLength: 20);
      expect(summary, contains('[OTP]'));
      expect(summary.length, lessThanOrEqualTo(23)); // 20 + '...'
    });
  });
}
