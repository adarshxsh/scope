import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_engine.dart';

void main() {
  group('PrivacyEngine Tests', () {
    late PrivacyEngine privacyEngine;

    setUp(() {
      privacyEngine = PrivacyEngine();
    });

    test('drops notification when package is in blacklist', () {
      privacyEngine.addBlacklistedPackage('com.signal.app');

      final notif = AppNotification(
        id: '1',
        packageName: 'com.signal.app',
        title: 'New Message',
        content: 'Hello world',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(privacyEngine.shouldDrop(notif), isTrue);
    });

    test('allows notification when package is not in blacklist', () {
      privacyEngine.addBlacklistedPackage('com.signal.app');

      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'New Message',
        content: 'Hello world',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(privacyEngine.shouldDrop(notif), isFalse);
    });

    test('drops OTP notifications when excludeOtpAndHealth is enabled', () {
      privacyEngine.setSensitiveCategoryRules(excludeOtpAndHealth: true);

      final otpNotif = AppNotification(
        id: '3',
        packageName: 'com.google.android.calendar',
        title: 'Verification Code',
        content: 'Use 352572 to verify your sign-in.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(privacyEngine.shouldDrop(otpNotif), isTrue);
    });

    test('drops Health notifications when excludeOtpAndHealth is enabled', () {
      privacyEngine.setSensitiveCategoryRules(excludeOtpAndHealth: true);

      final healthNotif = AppNotification(
        id: '4',
        packageName: 'com.health.app',
        title: 'Doctor Appointment',
        content: 'Your medical report is ready.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(privacyEngine.shouldDrop(healthNotif), isTrue);
    });

    test('drops Finance notifications when excludeFinance is enabled', () {
      privacyEngine.setSensitiveCategoryRules(excludeFinance: true);

      final financeNotif = AppNotification(
        id: '5',
        packageName: 'com.phonepe.app',
        title: 'Payment Received',
        content: 'Received ₹799 via UPI.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(privacyEngine.shouldDrop(financeNotif), isTrue);
    });

    test('sanitizes monetary amounts and OTP codes when field sanitization is enabled', () {
      privacyEngine.setFieldSanitization(true);

      final rawNotif = AppNotification(
        id: '6',
        packageName: 'com.bank.app',
        title: 'OTP for ₹249 payment',
        content: 'Your verification code is 604740 for ₹249 transaction.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final sanitized = privacyEngine.sanitize(rawNotif);

      expect(sanitized.title, contains('[AMOUNT REDACTED]'));
      expect(sanitized.content, contains('[AMOUNT REDACTED]'));
      expect(sanitized.content, contains('[REDACTED]'));
      expect(sanitized.content, isNot(contains('604740')));
    });
  });
}
