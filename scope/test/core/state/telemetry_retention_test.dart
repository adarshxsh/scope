import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late ProviderContainer container;
  late NotificationController controller;

  setUp(() async {
    db = AttentionDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
    controller = NotificationController(container: container);
    // Allow initial async load to finish
    await Future.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    controller.dispose();
    container.dispose();
    await db.close();
  });

  group('Telemetry & Retention Controller Unit Tests', () {
    test('setRetentionDays updates state and persists setting', () async {
      expect(controller.retentionDays, equals(7));

      await controller.setRetentionDays(3);
      expect(controller.retentionDays, equals(3));

      final persisted = await db.userSettingsDao.getRetentionDays();
      expect(persisted, equals(3));
    });

    test('setTelemetryEnabled updates state and persists setting', () async {
      expect(controller.telemetryEnabled, isTrue);

      await controller.setTelemetryEnabled(false);
      expect(controller.telemetryEnabled, isFalse);

      final persisted = await db.userSettingsDao.getTelemetryEnabled();
      expect(persisted, isFalse);
    });

    test('Telemetry disabled halts focus session logging', () async {
      await controller.setTelemetryEnabled(false);

      controller.startFocusSession();
      final sessions = await db.focusSessionDao.getAll();
      expect(sessions, isEmpty);

      controller.finishFocusSession();
      await Future.delayed(const Duration(milliseconds: 50));
      final active = await db.focusSessionDao.getActiveSession();
      expect(active, isNull);
    });

    test('Telemetry enabled logs focus session entries', () async {
      await controller.setTelemetryEnabled(true);

      controller.startFocusSession();
      var sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));

      controller.finishFocusSession();
      await Future.delayed(const Duration(milliseconds: 50));
      sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));
      expect(sessions.first.completion, isTrue);
    });

    test('Telemetry disabled halts daily brief logging on actions', () async {
      await controller.setTelemetryEnabled(false);

      controller.recordCalendarEvent();
      controller.recordReminder();
      controller.recordReviewed();
      await Future.delayed(const Duration(milliseconds: 50));

      final briefs = await db.dailyBriefDao.getAll();
      expect(briefs, isEmpty);
    });

    test('Telemetry enabled logs daily brief stats on actions', () async {
      await controller.setTelemetryEnabled(true);

      controller.recordCalendarEvent();
      await Future.delayed(const Duration(milliseconds: 50));

      final todayStr = DateTime.now().toIso8601String().split('T').first;
      final brief = await db.dailyBriefDao.getBriefForDate(todayStr);
      expect(brief, isNotNull);
      expect(brief!.calendarEventsCreated, equals(1));
    });

    test('runBackgroundCleanup uses retentionDays cutoff to prune records', () async {
      await controller.setRetentionDays(3);
      await Future.delayed(const Duration(milliseconds: 50));

      final oldDate = DateTime.now().subtract(const Duration(days: 5));
      final newDate = DateTime.now().subtract(const Duration(days: 1));

      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'old-1',
        packageName: 'com.test',
        title: 'Old',
        content: 'Content',
        timestamp: oldDate.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: oldDate,
      ));

      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'new-1',
        packageName: 'com.test',
        title: 'New',
        content: 'Content',
        timestamp: newDate.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: newDate,
      ));

      await controller.runBackgroundCleanup();

      final allNotifs = await db.notificationDao.getAll();
      expect(allNotifs.length, equals(1));
      expect(allNotifs.first.id, equals('new-1'));
    });
  });
}
