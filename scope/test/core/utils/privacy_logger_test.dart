import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/privacy_logger.dart';

void main() {
  group('PrivacyLogger', () {
    test('redacts cleartext OTP verification codes', () {
      const raw = 'Use 352572 to verify your sign-in. Valid for 15 minutes.';
      final sanitized = PrivacyLogger.sanitize(raw);

      expect(sanitized, contains('[OTP]'));
      expect(sanitized, isNot(contains('352572')));
      expect(sanitized, contains('Use [OTP] to verify your sign-in. Valid for 15 minutes.'));
    });

    test('redacts monetary transaction amounts', () {
      const raw = '₹249 electricity bill is due on 01 Jul.';
      final sanitized = PrivacyLogger.sanitize(raw);

      expect(sanitized, contains('[AMOUNT]'));
      expect(sanitized, isNot(contains('₹249')));
      expect(sanitized, contains('[AMOUNT] electricity bill is due on 01 Jul.'));
    });

    test('redacts email addresses and phone numbers', () {
      const raw = 'Contact user@example.com or +1 800-555-0199 for help.';
      final sanitized = PrivacyLogger.sanitize(raw);

      expect(sanitized, contains('[EMAIL]'));
      expect(sanitized, contains('[PHONE]'));
      expect(sanitized, isNot(contains('user@example.com')));
      expect(sanitized, isNot(contains('+1 800-555-0199')));
    });

    test('redacts order IDs and transaction identifiers', () {
      const raw = 'Your order #OD766563 has shipped. Txn ref: TXN98765432.';
      final sanitized = PrivacyLogger.sanitize(raw);

      expect(sanitized, contains('[ACCOUNT]'));
      expect(sanitized, isNot(contains('#OD766563')));
      expect(sanitized, isNot(contains('TXN98765432')));
    });

    test('preserves year numbers and execution metadata', () {
      const raw = 'Inference Time: 12500 us | year: 2026 | score: 85.50';
      final sanitized = PrivacyLogger.sanitize(raw);

      expect(sanitized, contains('12500 us'));
      expect(sanitized, contains('2026'));
      expect(sanitized, contains('85.50'));
    });

    test('sanitizes notification logging helper output', () {
      // Test logNotification produces sanitized output
      final text = PrivacyLogger.sanitize(
        'Captured: com.google.android.calendar - Verification code: 482910',
      );
      expect(text, isNot(contains('482910')));
      expect(text, contains('[OTP]'));
    });
  });
}
