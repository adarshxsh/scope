import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ingestion_guardrail_filter.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('IngestionGuardrailFilter Unit Tests', () {
    late IngestionGuardrailFilter filter;

    setUp(() {
      filter = IngestionGuardrailFilter();
    });

    test('Default config permits standard notifications', () {
      const notif = AppNotification(
        id: 'n1',
        packageName: 'com.google.android.gm',
        title: 'Work Email',
        content: 'Project roadmap discussion',
        timestamp: 1625097600000,
      );

      final result = filter.evaluate(notif);
      expect(result.isAllowed, isTrue);
      expect(result.sanitizedNotification, isNotNull);
      expect(filter.telemetry.totalEvaluated, equals(1));
      expect(filter.telemetry.totalIngested, equals(1));
    });

    test('Validation Guardrails: Rejects empty package name', () {
      const notif = AppNotification(
        id: 'n1',
        packageName: '   ',
        title: 'Test',
        content: 'Test content',
        timestamp: 1625097600000,
      );

      final result = filter.evaluate(notif);
      expect(result.isAllowed, isFalse);
      expect(result.reason, equals('invalid_package_name'));
      expect(filter.telemetry.totalRejectedValidation, equals(1));
    });

    test('Validation Guardrails: Rejects non-positive timestamp', () {
      const notif = AppNotification(
        id: 'n1',
        packageName: 'com.example.app',
        title: 'Test',
        content: 'Test content',
        timestamp: 0,
      );

      final result = filter.evaluate(notif);
      expect(result.isAllowed, isFalse);
      expect(result.reason, equals('invalid_timestamp'));
      expect(filter.telemetry.totalRejectedValidation, equals(1));
    });

    test('Validation Guardrails: Rejects timestamp in the future when disallowed', () {
      final futureTimestamp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.example.app',
        title: 'Test',
        content: 'Test content',
        timestamp: futureTimestamp,
      );

      final result = filter.evaluate(notif);
      expect(result.isAllowed, isFalse);
      expect(result.reason, equals('future_timestamp_exceeded'));
      expect(filter.telemetry.totalRejectedValidation, equals(1));
    });

    test('Validation Guardrails: Truncates title and content exceeding max length limits', () {
      filter.config = filter.config.copyWith(maxTitleLength: 10, maxContentLength: 15);
      const notif = AppNotification(
        id: 'n1',
        packageName: 'com.example.app',
        title: '1234567890EXTRA_TITLE',
        content: '123456789012345EXTRA_CONTENT',
        timestamp: 1625097600000,
      );

      final result = filter.evaluate(notif);
      expect(result.isAllowed, isTrue);
      expect(result.sanitizedNotification!.title, equals('1234567890'));
      expect(result.sanitizedNotification!.content, equals('123456789012345'));
    });

    test('Package Blacklist: Excludes notifications from blacklisted packages', () {
      filter.config = filter.config.copyWith(
        blacklistedPackages: {'com.spam.adverts', 'com.unwanted.tracker'},
      );

      const blacklistedNotif = AppNotification(
        id: 'n1',
        packageName: 'com.spam.adverts',
        title: 'Buy stuff',
        content: '50% off today',
        timestamp: 1625097600000,
      );

      const normalNotif = AppNotification(
        id: 'n2',
        packageName: 'com.normal.app',
        title: 'Hello',
        content: 'World',
        timestamp: 1625097600000,
      );

      expect(filter.evaluate(blacklistedNotif).isAllowed, isFalse);
      expect(filter.telemetry.totalExcludedBlacklist, equals(1));

      expect(filter.evaluate(normalNotif).isAllowed, isTrue);
      expect(filter.telemetry.totalIngested, equals(1));
    });

    test('Package Whitelist: Enforces Whitelist Mode', () {
      filter.config = filter.config.copyWith(
        isWhitelistModeEnabled: true,
        whitelistedPackages: {'com.whatsapp', 'com.slack'},
      );

      const whitelistedNotif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Meeting tomorrow',
        timestamp: 1625097600000,
      );

      const nonWhitelistedNotif = AppNotification(
        id: 'n2',
        packageName: 'com.random.game',
        title: 'Daily Reward',
        content: 'Claim free coins',
        timestamp: 1625097600000,
      );

      expect(filter.evaluate(whitelistedNotif).isAllowed, isTrue);

      final result = filter.evaluate(nonWhitelistedNotif);
      expect(result.isAllowed, isFalse);
      expect(result.reason, equals('package_not_whitelisted'));
      expect(filter.telemetry.totalExcludedWhitelist, equals(1));
    });

    test('Sensitive Category Exclusion: Detects and excludes Banking & Finance notifications', () {
      filter.config = filter.config.copyWith(
        excludedCategories: {SensitiveCategory.bankingFinance},
      );

      const bankNotif = AppNotification(
        id: 'n1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'Transaction Alert',
        content: 'Your account has been debited Rs 2,500 for transaction #8812',
        timestamp: 1625097600000,
      );

      final result = filter.evaluate(bankNotif);
      expect(result.isAllowed, isFalse);
      expect(result.sensitiveCategory, equals(SensitiveCategory.bankingFinance));
      expect(filter.telemetry.totalExcludedSensitiveCategory, equals(1));
    });

    test('Sensitive Category Exclusion: Detects and excludes OTP & Security notifications', () {
      filter.config = filter.config.copyWith(
        excludedCategories: {SensitiveCategory.otpSecurity},
      );

      const otpNotif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Verification Code',
        content: 'Use 883910 to verify your sign-in attempt. Valid for 10 minutes.',
        timestamp: 1625097600000,
        category: 'otp',
      );

      final result = filter.evaluate(otpNotif);
      expect(result.isAllowed, isFalse);
      expect(result.sensitiveCategory, equals(SensitiveCategory.otpSecurity));
      expect(filter.telemetry.totalExcludedSensitiveCategory, equals(1));
    });

    test('Sensitive Category Exclusion: Detects and excludes Health & Medical notifications', () {
      filter.config = filter.config.copyWith(
        excludedCategories: {SensitiveCategory.healthMedical},
      );

      const healthNotif = AppNotification(
        id: 'n1',
        packageName: 'com.apollo.patientapp',
        title: 'Prescription Update',
        content: 'Your doctor appointment summary and prescription report are ready.',
        timestamp: 1625097600000,
      );

      final result = filter.evaluate(healthNotif);
      expect(result.isAllowed, isFalse);
      expect(result.sensitiveCategory, equals(SensitiveCategory.healthMedical));
      expect(filter.telemetry.totalExcludedSensitiveCategory, equals(1));
    });

    test('Sensitive Category Exclusion: Detects and excludes Personal Messaging notifications', () {
      filter.config = filter.config.copyWith(
        excludedCategories: {SensitiveCategory.personalMessaging},
      );

      const msgNotif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Bob',
        content: 'Hey, are you free for lunch?',
        timestamp: 1625097600000,
        category: 'msg',
      );

      final result = filter.evaluate(msgNotif);
      expect(result.isAllowed, isFalse);
      expect(result.sensitiveCategory, equals(SensitiveCategory.personalMessaging));
      expect(filter.telemetry.totalExcludedSensitiveCategory, equals(1));
    });

    test('Telemetry summary reports accurate counts and resets properly', () {
      filter.config = filter.config.copyWith(
        blacklistedPackages: {'com.spam'},
        excludedCategories: {SensitiveCategory.otpSecurity},
      );

      const validNotif = AppNotification(
        id: 'n1',
        packageName: 'com.valid.app',
        title: 'Hello',
        content: 'Test',
        timestamp: 1625097600000,
      );

      const blacklistedNotif = AppNotification(
        id: 'n2',
        packageName: 'com.spam',
        title: 'Spam',
        content: 'Spam',
        timestamp: 1625097600000,
      );

      const otpNotif = AppNotification(
        id: 'n3',
        packageName: 'com.auth.app',
        title: 'OTP Code',
        content: 'Your OTP code is 123456',
        timestamp: 1625097600000,
      );

      filter.evaluate(validNotif);
      filter.evaluate(blacklistedNotif);
      filter.evaluate(otpNotif);

      expect(filter.telemetry.totalEvaluated, equals(3));
      expect(filter.telemetry.totalIngested, equals(1));
      expect(filter.telemetry.totalExcludedBlacklist, equals(1));
      expect(filter.telemetry.totalExcludedSensitiveCategory, equals(1));

      filter.telemetry.reset();
      expect(filter.telemetry.totalEvaluated, equals(0));
      expect(filter.telemetry.totalIngested, equals(0));
    });
  });
}
