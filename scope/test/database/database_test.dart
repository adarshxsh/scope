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

    test('UserSettingsDao default creation and boundary validation', () async {
      var settings = await db.userSettingsDao.getUserSettings();
      expect(settings.retentionDays, equals(7));
      expect(settings.telemetryEnabled, isTrue);
      expect(settings.storageQuotaMb, equals(25));
      expect(settings.maxRowCap, equals(5000));

      // Test valid update
      await db.userSettingsDao.updateUserSettings(
        retentionDays: 14,
        telemetryEnabled: false,
        storageQuotaMb: 50,
        maxRowCap: 10000,
      );

      settings = await db.userSettingsDao.getUserSettings();
      expect(settings.retentionDays, equals(14));
      expect(settings.telemetryEnabled, isFalse);
      expect(settings.storageQuotaMb, equals(50));
      expect(settings.maxRowCap, equals(10000));

      // Test invalid boundaries (should be rejected/ignored, keeping previous valid values)
      await db.userSettingsDao.updateUserSettings(
        retentionDays: 9999, // Invalid (>365 and != -1)
        storageQuotaMb: 1,    // Invalid (<5)
        maxRowCap: 10,        // Invalid (<100)
      );

      settings = await db.userSettingsDao.getUserSettings();
      expect(settings.retentionDays, equals(14));
      expect(settings.storageQuotaMb, equals(50));
      expect(settings.maxRowCap, equals(10000));
    });

    test('InferenceTelemetryDao logs events when enabled and bypasses when disabled', () async {
      await db.userSettingsDao.updateUserSettings(telemetryEnabled: true);

      await db.inferenceTelemetryDao.logEvent(InferenceTelemetryTableCompanion.insert(
        notificationId: const Value('n1'),
        eventType: 'inference',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        latencyMs: const Value(12),
        priority: const Value('high'),
        fusedScore: const Value(85.0),
        metadata: const Value('{"category":"finance"}'),
      ));

      var count = await db.inferenceTelemetryDao.getTelemetryCount();
      expect(count, equals(1));

      // Disable telemetry logging
      await db.userSettingsDao.updateUserSettings(telemetryEnabled: false);

      await db.inferenceTelemetryDao.logEvent(InferenceTelemetryTableCompanion.insert(
        notificationId: const Value('n2'),
        eventType: 'inference',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        latencyMs: const Value(10),
        priority: const Value('low'),
        fusedScore: const Value(10.0),
        metadata: const Value('{"category":"promo"}'),
      ));

      // Count should remain 1 because telemetry was disabled
      count = await db.inferenceTelemetryDao.getTelemetryCount();
      expect(count, equals(1));

      // Clear all
      await db.inferenceTelemetryDao.clearAll();
      count = await db.inferenceTelemetryDao.getTelemetryCount();
      expect(count, equals(0));
    });

    test('runSetBasedCleanup respects user retention settings and row cap eviction', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final fourDaysOld = DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch;
      final tenDaysOld = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;

      for (int i = 1; i <= 5; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'n-$i',
          packageName: 'com.app',
          title: 'Notif $i',
          content: 'Content $i',
          timestamp: i == 1 ? tenDaysOld : (i == 2 ? fourDaysOld : nowMs + i),
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        ));
      }

      // Configure retentionDays = 7
      await db.userSettingsDao.updateUserSettings(retentionDays: 7);

      await db.runSetBasedCleanup(null, 3);

      final notifs = await db.notificationDao.getAll();
      // Should be trimmed down to maxRowCap = 3
      expect(notifs.length, equals(3));
      // 10 days old item (n-1) was deleted by age retention, then excess was trimmed to 3
      expect(notifs.any((n) => n.id == 'n-1'), isFalse);
    });
  });
}
