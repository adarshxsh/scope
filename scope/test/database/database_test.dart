import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  late AttentionDatabase db;

  setUp(() {
    // Instantiate in-memory database for testing
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift Database Unit Tests', () {
    test('NotificationDao insert and lookup by ID', () async {
      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('n1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Alice'));
      expect(fetched.content, equals('Hello'));
      expect(fetched.state, equals(ReviewState.ACTIVE));
    });

    test('NotificationDao upsert behavior', () async {
      final now = DateTime.now();
      final entry1 = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      final entry2 = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello (Updated)',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry1);
      await db.notificationDao.insertNotification(entry2);

      final fetched = await db.notificationDao.getById('n1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals('Hello (Updated)'));
    });

    test('ReviewQueueDao insert, updateStatus, and delete', () async {
      final now = DateTime.now();
      final qEntry = ReviewQueueEntry(
        id: 1,
        notificationId: 'n1',
        priority: 'high',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      );

      await db.reviewQueueDao.insertItem(qEntry);

      var list = await db.reviewQueueDao.getAll();
      expect(list.length, equals(1));
      expect(list.first.priority, equals('high'));
      expect(list.first.status, equals(ReviewState.ACTIVE));

      await db.reviewQueueDao.updateStatus('n1', ReviewState.SNOOZED);
      list = await db.reviewQueueDao.getAll();
      expect(list.first.status, equals(ReviewState.SNOOZED));

      await db.reviewQueueDao.deleteItem('n1');
      list = await db.reviewQueueDao.getAll();
      expect(list, isEmpty);
    });

    test('FocusSessionDao active session tracking', () async {
      final now = DateTime.now();
      final session = FocusSessionEntry(
        id: 1,
        sessionStart: now,
        interruptions: 2,
        completion: false,
        duration: 0,
      );

      await db.focusSessionDao.insertSession(session);

      var active = await db.focusSessionDao.getActiveSession();
      expect(active, isNotNull);
      expect(active!.interruptions, equals(2));
      expect(active.completion, isFalse);

      final endedSession = session.copyWith(
        sessionEnd: Value(now.add(const Duration(minutes: 5))),
        completion: true,
        duration: 300,
      );
      await db.focusSessionDao.updateSession(endedSession);

      active = await db.focusSessionDao.getActiveSession();
      expect(active, isNull);

      final all = await db.focusSessionDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.completion, isTrue);
      expect(all.first.duration, equals(300));
    });

    test('DailyBriefDao stats increment and lookup', () async {
      final date = '2026-06-27';
      final entry = DailyBriefEntry(
        id: 1,
        date: date,
        notificationsReviewed: 5,
        actionsCompleted: 2,
        calendarEventsCreated: 1,
        remindersCreated: 1,
        archivedCount: 3,
      );

      await db.dailyBriefDao.insertOrUpdate(entry);

      var brief = await db.dailyBriefDao.getBriefForDate(date);
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, equals(5));

      await db.dailyBriefDao.incrementStats(date, reviewed: 2, completed: 1);
      brief = await db.dailyBriefDao.getBriefForDate(date);
      expect(brief!.notificationsReviewed, equals(7));
      expect(brief.actionsCompleted, equals(3));
    });

    test('NotificationDao deleteOlderThan cleanup', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      final newTime = DateTime.now().millisecondsSinceEpoch;

      final nOld = NotificationEntry(
        id: 'n-old',
        packageName: 'whatsapp',
        title: 'Old',
        content: 'Body',
        timestamp: oldTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      final nNew = NotificationEntry(
        id: 'n-new',
        packageName: 'whatsapp',
        title: 'New',
        content: 'Body',
        timestamp: newTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(nOld);
      await db.notificationDao.insertNotification(nNew);

      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final deleted = await db.notificationDao.deleteOlderThan(cutoff);
      expect(deleted, equals(1));

      final all = await db.notificationDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.id, equals('n-new'));
    });

    test('runSetBasedCleanup removes expired notifications and orphaned review queue items', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      final newTime = DateTime.now().millisecondsSinceEpoch;

      final nOld = NotificationEntry(
        id: 'n-old',
        packageName: 'whatsapp',
        title: 'Old',
        content: 'Body',
        timestamp: oldTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      final nNew = NotificationEntry(
        id: 'n-new',
        packageName: 'whatsapp',
        title: 'New',
        content: 'Body',
        timestamp: newTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(nOld);
      await db.notificationDao.insertNotification(nNew);

      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 1,
        notificationId: 'n-old',
        priority: 'high',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));
      
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 2,
        notificationId: 'n-new',
        priority: 'high',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      // This one is already orphaned before cleanup
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 3,
        notificationId: 'n-missing',
        priority: 'low',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      await db.runSetBasedCleanup(cutoff);

      final notifications = await db.notificationDao.getAll();
      expect(notifications.length, equals(1));
      expect(notifications.first.id, equals('n-new'));

      final queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      // Only the new one should remain, old one deleted due to notification expiry
      // Missing one deleted due to being orphaned
      expect(queueItems.first.notificationId, equals('n-new'));
    });

    test('UserSettingsDao set and get retention and telemetry settings', () async {
      // Defaults
      final defaultRetention = await db.userSettingsDao.getRetentionDays();
      expect(defaultRetention, equals(7));

      final defaultTelemetry = await db.userSettingsDao.getTelemetryEnabled();
      expect(defaultTelemetry, isTrue);

      // Save custom retention
      await db.userSettingsDao.setRetentionDays(3);
      final updatedRetention = await db.userSettingsDao.getRetentionDays();
      expect(updatedRetention, equals(3));

      // Save custom telemetry
      await db.userSettingsDao.setTelemetryEnabled(false);
      final updatedTelemetry = await db.userSettingsDao.getTelemetryEnabled();
      expect(updatedTelemetry, isFalse);
    });

    test('FocusSessionDao deleteOlderThan prunes expired sessions', () async {
      final oldStart = DateTime.now().subtract(const Duration(days: 10));
      final newStart = DateTime.now().subtract(const Duration(days: 2));

      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 1,
        sessionStart: oldStart,
        sessionEnd: oldStart.add(const Duration(minutes: 15)),
        interruptions: 0,
        completion: true,
        duration: 900,
      ));

      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 2,
        sessionStart: newStart,
        sessionEnd: newStart.add(const Duration(minutes: 15)),
        interruptions: 1,
        completion: true,
        duration: 900,
      ));

      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final deleted = await db.focusSessionDao.deleteOlderThan(cutoff);
      expect(deleted, equals(1));

      final sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));
      expect(sessions.first.id, equals(2));
    });

    test('DailyBriefDao deleteOlderThan prunes expired brief records', () async {
      final oldDate = '2026-01-01';
      final newDate = '2026-09-15';

      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 1,
        date: oldDate,
        notificationsReviewed: 10,
        actionsCompleted: 5,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 2,
      ));

      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 2,
        date: newDate,
        notificationsReviewed: 3,
        actionsCompleted: 1,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 1,
      ));

      final cutoff = DateTime(2026, 9, 10);
      final deleted = await db.dailyBriefDao.deleteOlderThan(cutoff);
      expect(deleted, equals(1));

      final briefs = await db.dailyBriefDao.getAll();
      expect(briefs.length, equals(1));
      expect(briefs.first.date, equals(newDate));
    });

    test('runSetBasedCleanup prunes across notifications, review queue, focus sessions, and daily briefs in single transaction', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 10));
      final newTime = DateTime.now().subtract(const Duration(days: 1));

      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'old-notif',
        packageName: 'app',
        title: 'Old',
        content: 'Body',
        timestamp: oldTime.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: oldTime,
      ));

      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 1,
        sessionStart: oldTime,
        sessionEnd: oldTime.add(const Duration(minutes: 10)),
        interruptions: 0,
        completion: true,
        duration: 600,
      ));

      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 1,
        date: '2020-01-01',
        notificationsReviewed: 5,
        actionsCompleted: 2,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 1,
      ));

      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      await db.runSetBasedCleanup(cutoff);

      expect(await db.notificationDao.getAll(), isEmpty);
      expect(await db.focusSessionDao.getAll(), isEmpty);
      expect(await db.dailyBriefDao.getAll(), isEmpty);
    });
  });
}
