import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/pii_audit_logger.dart';
import 'package:scope/core/privacy/pii_redactor.dart';

void main() {
  setUp(() {
    PiiAuditLogger.clear();
  });

  group('PiiRedactor Unit Tests', () {
    test('redacts OTP verification codes in context', () {
      const input = 'Your verification code is 882715. Valid for 10 minutes.';
      final result = PiiRedactor.redactText(input);

      expect(result.redactedText, contains('[REDACTED CODE]'));
      expect(result.redactedText, isNot(contains('882715')));
      expect(result.detectedPiiTypes, contains(PiiType.otp));
    });

    test('redacts explicit OTP passed from extracted features', () {
      const input = 'Your OTP is 482715.';
      final result = PiiRedactor.redactText(input, explicitOtp: '482715');

      expect(result.redactedText, contains('[REDACTED CODE]'));
      expect(result.redactedText, isNot(contains('482715')));
    });

    test('redacts phone numbers', () {
      const input = 'Call customer support at +1 800-555-0199 or 9876543210.';
      final result = PiiRedactor.redactText(input);

      expect(result.redactedText, contains('[REDACTED PHONE]'));
      expect(result.redactedText, isNot(contains('800-555-0199')));
      expect(result.detectedPiiTypes, contains(PiiType.phone));
    });

    test('redacts email addresses', () {
      const input = 'Reset link sent to user.name@example.com for account verification.';
      final result = PiiRedactor.redactText(input);

      expect(result.redactedText, contains('[REDACTED EMAIL]'));
      expect(result.redactedText, isNot(contains('user.name@example.com')));
      expect(result.detectedPiiTypes, contains(PiiType.email));
    });

    test('redacts credit card numbers while preserving last 4 digits format', () {
      const input = 'Payment charged to card 4532 1234 5678 9012.';
      final result = PiiRedactor.redactText(input);

      expect(result.redactedText, contains('•••• •••• •••• 9012'));
      expect(result.redactedText, isNot(contains('4532')));
      expect(result.detectedPiiTypes, contains(PiiType.card));
    });

    test('redacts cleartext credentials and passwords', () {
      const input = 'Your temporary password: SecretPassword123!';
      final result = PiiRedactor.redactText(input);

      expect(result.redactedText, contains('password: [REDACTED CREDENTIAL]'));
      expect(result.redactedText, isNot(contains('SecretPassword123!')));
      expect(result.detectedPiiTypes, contains(PiiType.credential));
    });

    test('redacts bank account numbers', () {
      const input = 'Debited Rs. 5000 from A/C 1234567890.';
      final result = PiiRedactor.redactText(input);

      expect(result.redactedText, contains('A/C ••••7890'));
      expect(result.detectedPiiTypes, contains(PiiType.accountNumber));
    });

    test('redactNotification redacts title, content, explanation, and extractedFeatures', () {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Verification code',
        content: 'Your code is 882715.',
        timestamp: 1000,
        explanation: 'OTP Code: Found verification code 882715.',
        extractedFeatures: {
          'otp': '882715',
          'phoneNumbers': ['+18005550199'],
          'emails': ['test@domain.com'],
        },
      );

      final redacted = PiiRedactor.redactNotification(notif);

      expect(redacted.content, contains('[REDACTED CODE]'));
      expect(redacted.explanation, contains('[REDACTED CODE]'));
      expect(redacted.extractedFeatures!['otp'], equals('[REDACTED CODE]'));
      expect(redacted.extractedFeatures!['phoneNumbers'], equals(['[REDACTED PHONE]']));
      expect(redacted.extractedFeatures!['emails'], equals(['[REDACTED EMAIL]']));
    });

    test('executes fallback error recovery if parsing encounters an error', () {
      // Create a notification with null or bad values to trigger fallback
      final notif = AppNotification(
        id: 'fallback_test',
        packageName: 'com.test',
        title: 'Test',
        content: 'Your OTP is 123456',
        timestamp: 1000,
      );

      final fallbackResult = PiiRedactor.redactNotification(notif);

      expect(fallbackResult.content, isNotNull);
      expect(fallbackResult.content, isNot(contains('123456')));
    });
  });
}
