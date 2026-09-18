import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/privacy_sanitizer.dart';

void main() {
  group('PrivacySanitizer Tests', () {
    test('sanitizeText redacts email addresses', () {
      final input = 'Contact user john.doe@example.com for support.';
      final sanitized = PrivacySanitizer.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, isNot(contains('john.doe@example.com')));
    });

    test('sanitizeText redacts phone numbers', () {
      final input = 'Call +1-555-0199 or 9876543210 for account verification.';
      final sanitized = PrivacySanitizer.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_PHONE]'));
      expect(sanitized, isNot(contains('+1-555-0199')));
    });

    test('sanitizeText redacts OTP verification codes when context present', () {
      final input = 'Your verification code is 883102. Valid for 5 minutes.';
      final sanitized = PrivacySanitizer.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_OTP]'));
      expect(sanitized, isNot(contains('883102')));
    });

    test('sanitizeText redacts 16-digit credit card numbers', () {
      final input = 'Card 4111222233334444 debited Rs 1200.';
      final sanitized = PrivacySanitizer.sanitizeText(input);
      expect(sanitized, contains('[REDACTED_ACCOUNT]'));
      expect(sanitized, isNot(contains('4111222233334444')));
    });

    test('sanitizeNotification redacts title, content, and explanation', () {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Security Code',
        content: 'Your code is 552109 sent to user@domain.com',
        timestamp: 1000,
        explanation: 'Verification code for user@domain.com',
      );

      final sanitized = PrivacySanitizer.sanitizeNotification(notif);
      expect(sanitized.content, contains('[REDACTED_OTP]'));
      expect(sanitized.content, contains('[REDACTED_EMAIL]'));
      expect(sanitized.explanation, contains('[REDACTED_EMAIL]'));
    });

    test('validateNotificationSchema throws on empty ID or invalid bounds', () {
      expect(
        () => PrivacySanitizer.validateNotificationSchema(
          const AppNotification(id: '', packageName: 'app', title: 't', content: 'c', timestamp: 100),
        ),
        throwsFormatException,
      );

      expect(
        () => PrivacySanitizer.validateNotificationSchema(
          const AppNotification(id: '1', packageName: 'app', title: 't', content: 'c', timestamp: -5),
        ),
        throwsFormatException,
      );

      expect(
        PrivacySanitizer.validateNotificationSchema(
          const AppNotification(id: '1', packageName: 'app', title: 'Valid', content: 'Body', timestamp: 1000),
        ),
        isTrue,
      );
    });
  });
}
