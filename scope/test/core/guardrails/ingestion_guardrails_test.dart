import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/guardrails/ingestion_guardrails.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('IngestionGuardrailService Tests', () {
    late IngestionGuardrailService service;

    setUp(() {
      service = IngestionGuardrailService();
    });

    test('Allows standard valid notification', () {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.example.chat',
        title: 'Meeting Alert',
        content: 'Your meeting is starting in 10 minutes',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        category: 'msg',
      );

      final result = service.evaluate(notif);
      expect(result.isAllowed, isTrue);
      expect(result.dropReason, isNull);
      expect(result.sanitizedNotification.title, equals('Meeting Alert'));
    });

    test('Blocks blacklisted packages by default', () {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.android.systemui',
        title: 'System UI Alert',
        content: 'System overlay displayed',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = service.evaluate(notif);
      expect(result.isAllowed, isFalse);
      expect(result.dropReason, equals('blacklisted_package'));
    });

    test('Blocks ongoing notifications', () {
      final notif = AppNotification(
        id: '3',
        packageName: 'com.example.music',
        title: 'Playing Music',
        content: 'Track title - Artist',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isOngoing: true,
      );

      final result = service.evaluate(notif);
      expect(result.isAllowed, isFalse);
      expect(result.dropReason, equals('ongoing_notification'));
    });

    test('Enforces package whitelisting when enabled', () {
      service.updatePolicy(
        service.policy.copyWith(
          isWhitelistingEnabled: true,
          whitelistedPackages: {'com.whitelisted.app'},
        ),
      );

      final allowedNotif = AppNotification(
        id: '4',
        packageName: 'com.whitelisted.app',
        title: 'Whitelisted App',
        content: 'Content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final blockedNotif = AppNotification(
        id: '5',
        packageName: 'com.unapproved.app',
        title: 'Unapproved App',
        content: 'Content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(service.evaluate(allowedNotif).isAllowed, isTrue);
      final blockedResult = service.evaluate(blockedNotif);
      expect(blockedResult.isAllowed, isFalse);
      expect(blockedResult.dropReason, equals('not_whitelisted_package'));
    });

    test('Excludes background system and progress categories', () {
      final progressNotif = AppNotification(
        id: '6',
        packageName: 'com.example.downloader',
        title: 'Downloading file',
        content: '50% completed (50 MB / 100 MB)',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        category: 'progress',
      );

      final result = service.evaluate(progressNotif);
      expect(result.isAllowed, isFalse);
      expect(result.dropReason, equals('excluded_category'));
    });

    test('Truncates title and content exceeding max limits', () {
      final longTitle = 'T' * 600;
      final longContent = 'C' * 2500;

      final notif = AppNotification(
        id: '7',
        packageName: 'com.example.news',
        title: longTitle,
        content: longContent,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = service.evaluate(notif);
      expect(result.isAllowed, isTrue);
      expect(result.sanitizedNotification.title.length, equals(500));
      expect(result.sanitizedNotification.content.length, equals(2000));
    });

    test('Blocks empty payload notifications', () {
      final notif = AppNotification(
        id: '8',
        packageName: 'com.example.empty',
        title: '   ',
        content: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = service.evaluate(notif);
      expect(result.isAllowed, isFalse);
      expect(result.dropReason, equals('empty_payload'));
    });

    test('Records audit log and caps at maximum entries', () {
      for (int i = 0; i < 110; i++) {
        final notif = AppNotification(
          id: '$i',
          packageName: 'com.example.app_$i',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        service.evaluate(notif);
      }

      expect(service.auditLogs.length, equals(IngestionGuardrailService.maxAuditLogs));
    });
  });
}
