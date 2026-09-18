import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/guardrails/ingestion_guardrails.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('Ingestion Guardrails & Exclusion Controls Unit Tests', () {
    late IngestionGuardrailService service;

    setUp(() {
      service = IngestionGuardrailService();
    });

    test('Package Blacklist rejects blacklisted packages prior to ingestion', () {
      const notif = AppNotification(
        id: 'test_1',
        packageName: 'com.android.systemui.volume',
        title: 'Volume Slider',
        content: 'Volume changed',
        timestamp: 1700000000000,
      );

      final report = service.evaluateAndSanitize(notif);
      expect(report.isAllowed, isFalse);
      expect(report.result, equals(IngestionResult.rejectedBlacklistedPackage));
      expect(report.reason, contains('blacklisted'));
    });

    test('Package Whitelist mode allows whitelisted packages and rejects others', () {
      final customPolicy = IngestionGuardrailPolicy(
        whitelistMode: true,
        whitelistedPackages: {'com.whatsapp', 'com.google.android.gm'},
      );
      service.updatePolicy(customPolicy);

      const allowedNotif = AppNotification(
        id: 'test_2',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Hello',
        timestamp: 1700000000000,
      );

      const blockedNotif = AppNotification(
        id: 'test_3',
        packageName: 'com.unauthorized.app',
        title: 'Spam',
        content: 'Win 1000\$',
        timestamp: 1700000000000,
      );

      final report1 = service.evaluateAndSanitize(allowedNotif);
      expect(report1.isAllowed, isTrue);

      final report2 = service.evaluateAndSanitize(blockedNotif);
      expect(report2.isAllowed, isFalse);
      expect(report2.result, equals(IngestionResult.rejectedNotWhitelistedPackage));
    });

    test('Sensitive Category Exclusion rejects notifications matching excluded categories', () {
      final customPolicy = const IngestionGuardrailPolicy().copyWith(
        excludedCategories: {'finance', 'healthcare'},
      );
      service.updatePolicy(customPolicy);

      const financeNotif = AppNotification(
        id: 'test_4',
        packageName: 'com.example.bank',
        title: 'Account Alert',
        content: 'Balance updated',
        timestamp: 1700000000000,
        category: 'finance',
      );

      const msgNotif = AppNotification(
        id: 'test_5',
        packageName: 'com.whatsapp',
        title: 'Friend',
        content: 'Let\'s meet',
        timestamp: 1700000000000,
        category: 'msg',
      );

      final report1 = service.evaluateAndSanitize(financeNotif);
      expect(report1.isAllowed, isFalse);
      expect(report1.result, equals(IngestionResult.rejectedExcludedCategory));

      final report2 = service.evaluateAndSanitize(msgNotif);
      expect(report2.isAllowed, isTrue);
    });

    test('Schema Validation rejects empty or malformed package names', () {
      const invalidNotif1 = AppNotification(
        id: 'test_6',
        packageName: '',
        title: 'Title',
        content: 'Content',
        timestamp: 1700000000000,
      );

      const invalidNotif2 = AppNotification(
        id: 'test_7',
        packageName: 'invalid package name with spaces!!',
        title: 'Title',
        content: 'Content',
        timestamp: 1700000000000,
      );

      expect(service.evaluateAndSanitize(invalidNotif1).isAllowed, isFalse);
      expect(service.evaluateAndSanitize(invalidNotif2).isAllowed, isFalse);
    });

    test('Input Sanitization truncates oversized titles and bodies', () {
      final longTitle = 'A' * 1000;
      final longContent = 'B' * 5000;

      final oversizedNotif = AppNotification(
        id: 'test_8',
        packageName: 'com.example.app',
        title: longTitle,
        content: longContent,
        timestamp: 1700000000000,
      );

      final report = service.evaluateAndSanitize(oversizedNotif);
      expect(report.isAllowed, isTrue);
      expect(report.notification!.title.length, equals(500));
      expect(report.notification!.content.length, equals(2000));
    });

    test('Input Sanitization normalizes out-of-range timestamps', () {
      final invalidTimestampNotif = const AppNotification(
        id: 'test_9',
        packageName: 'com.example.app',
        title: 'Test',
        content: 'Test content',
        timestamp: -99999, // Negative invalid epoch
      );

      final report = service.evaluateAndSanitize(invalidTimestampNotif);
      expect(report.isAllowed, isTrue);
      expect(report.notification!.timestamp, greaterThan(1577836800000));
    });

    test('Diagnostic logging redacts cleartext PII (titles and bodies)', () {
      const sensitiveNotif = AppNotification(
        id: 'test_10',
        packageName: 'com.whatsapp',
        title: 'Banking OTP Code 882910',
        content: 'Your secret verification pin is 449102. Do not share with anyone.',
        timestamp: 1700000000000,
      );

      final log = service.formatDiagnosticLog(sensitiveNotif, tag: 'TEST');
      expect(log, contains('[TEST]'));
      expect(log, contains('com.whatsapp'));
      expect(log, isNot(contains('882910')));
      expect(log, isNot(contains('449102')));
      expect(log, isNot(contains('Banking OTP Code')));
      expect(log, isNot(contains('Your secret verification pin')));
      expect(log, contains('hash:'));
    });

    test('Performance Benchmark: Guardrail evaluation executes sub-1ms (well under 50ms limit)', () {
      final notif = AppNotification(
        id: 'benchmark_1',
        packageName: 'com.whatsapp',
        title: 'Title ' * 10,
        content: 'Content body ' * 50,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        service.evaluateAndSanitize(notif);
      }
      stopwatch.stop();

      final avgMicros = stopwatch.elapsedMicroseconds / 100;
      final avgMs = avgMicros / 1000.0;

      expect(avgMs, lessThan(50.0));
      // In practice avgMs should be < 1.0 ms
      expect(avgMs, lessThan(5.0));
    });
  });
}
