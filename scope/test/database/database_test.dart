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

    test('UserSettingsDao getSettings default values', () async {
      final settings = await db.userSettingsDao.getSettings();
      expect(settings.retentionDays, equals(7));
      expect(settings.telemetryEnabled, isTrue);
      expect(settings.maxRowCap, equals(5000));
      expect(settings.maxStorageMb, equals(25));
    });

    test('UserSettingsDao updateSettings and validation guardrails', () async {
      await db.userSettingsDao.updateSettings(
        retentionDays: 14,
        telemetryEnabled: false,
        maxRowCap: 2000,
        maxStorageMb: 50,
      );

      var settings = await db.userSettingsDao.getSettings();
      expect(settings.retentionDays, equals(14));
      expect(settings.telemetryEnabled, isFalse);
      expect(settings.maxRowCap, equals(2000));
      expect(settings.maxStorageMb, equals(50));

      // Test invalid inputs triggering fallback guardrails
      await db.userSettingsDao.updateSettings(
        retentionDays: -5, // Invalid negative retention
        maxRowCap: 0, // Invalid zero row cap
        maxStorageMb: -10, // Invalid storage MB
      );

      settings = await db.userSettingsDao.getSettings();
      expect(settings.retentionDays, equals(7)); // Fallback to 7
      expect(settings.maxRowCap, equals(5000)); // Fallback to 5000
      expect(settings.maxStorageMb, equals(25)); // Fallback to 25
    });

    test('runSetBasedCleanup enforces row cap limits', () async {
      final now = DateTime.now();
      // Insert 10 notifications with increasing timestamps
      for (int i = 0; i < 10; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'item-$i',
          packageName: 'com.whatsapp',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: now.millisecondsSinceEpoch + (i * 1000),
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ));
      }

      var all = await db.notificationDao.getAll();
      expect(all.length, equals(10));

      // Run cleanup enforcing a row cap of 4 items
      await db.runSetBasedCleanup(0, maxRowCap: 4);

      all = await db.notificationDao.getAll();
      expect(all.length, equals(4));
      // Oldest items (0..5) should be purged, newest items (6..9) remain
      expect(all.map((n) => n.id), containsAll(['item-6', 'item-7', 'item-8', 'item-9']));
    });

    test('runSetBasedCleanup handles unlimited retention (-1 / 0 cutoff)', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 100)).millisecondsSinceEpoch;
      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'ancient-item',
        packageName: 'com.whatsapp',
        title: 'Ancient',
        content: 'Body',
        timestamp: oldTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));

      // Cutoff 0 means unlimited retention (no timestamp deletion)
      await db.runSetBasedCleanup(0);

      final all = await db.notificationDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.id, equals('ancient-item'));
    });

    test('runSetBasedCleanup clears daily brief when clearTelemetry is true', () async {
      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 1,
        date: '2026-09-18',
        notificationsReviewed: 10,
        actionsCompleted: 5,
        calendarEventsCreated: 2,
        remindersCreated: 1,
        archivedCount: 3,
      ));

      var briefs = await db.dailyBriefDao.getAll();
      expect(briefs.length, equals(1));

      await db.runSetBasedCleanup(0, clearTelemetry: true);

      briefs = await db.dailyBriefDao.getAll();
      expect(briefs, isEmpty);
    });

    test('UserSettingsDao getStorageStats reports accurate counts', () async {
      final now = DateTime.now();
      for (int i = 0; i < 5; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'n-$i',
          packageName: 'com.whatsapp',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: now.millisecondsSinceEpoch + i,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ));
      }

      final stats = await db.userSettingsDao.getStorageStats();
      expect(stats.totalNotifications, equals(5));
      expect(stats.maxStorageMb, equals(25));
      expect(stats.maxRowCap, equals(5000));
    });
  });
}

