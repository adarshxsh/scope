import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

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

    test('NotificationDao enforces row capping and FIFO eviction prioritizing archived entries', () async {
      // Create custom dao with maxRows = 5
      final customDao = NotificationDao(db, maxRows: 5);
      final baseTime = DateTime.now().millisecondsSinceEpoch;

      // Insert 3 active notifications
      for (int i = 1; i <= 3; i++) {
        await customDao.insertNotification(NotificationEntry(
          id: 'active-$i',
          packageName: 'app',
          title: 'Active $i',
          content: 'Content',
          timestamp: baseTime + i * 100,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        ));
      }

      // Insert 2 archived notifications (older timestamp)
      for (int i = 1; i <= 2; i++) {
        await customDao.insertNotification(NotificationEntry(
          id: 'archived-$i',
          packageName: 'app',
          title: 'Archived $i',
          content: 'Content',
          timestamp: baseTime + i * 10,
          state: ReviewState.ARCHIVED,
          reviewed: true,
          dismissed: true,
          isOngoing: false,
          createdAt: DateTime.now(),
        ));
      }

      var count = await customDao.getCount();
      expect(count, equals(5));

      // Now insert 2 new active notifications (batch or single) -> count exceeds 5 by 2
      await customDao.insertNotification(NotificationEntry(
        id: 'new-1',
        packageName: 'app',
        title: 'New 1',
        content: 'Content',
        timestamp: baseTime + 1000,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));

      await customDao.insertNotification(NotificationEntry(
        id: 'new-2',
        packageName: 'app',
        title: 'New 2',
        content: 'Content',
        timestamp: baseTime + 1100,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));

      count = await customDao.getCount();
      expect(count, equals(5));

      // Verify the 2 archived entries were evicted first (FIFO order among archived entries)
      final archived1 = await customDao.getById('archived-1');
      final archived2 = await customDao.getById('archived-2');
      expect(archived1, isNull);
      expect(archived2, isNull);

      // Verify active entries were preserved
      final active1 = await customDao.getById('active-1');
      expect(active1, isNotNull);
    });

    test('runSetBasedCleanup prunes focus sessions and daily briefs older than 30 days', () async {
      final now = DateTime.now();
      final old35Days = now.subtract(const Duration(days: 35));
      final recent10Days = now.subtract(const Duration(days: 10));

      // Focus Sessions
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 1,
        sessionStart: old35Days,
        interruptions: 0,
        completion: false,
        duration: 300,
      ));
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 2,
        sessionStart: recent10Days,
        interruptions: 0,
        completion: false,
        duration: 300,
      ));

      // Daily Briefs
      final oldDate = '${old35Days.year.toString().padLeft(4, '0')}-${old35Days.month.toString().padLeft(2, '0')}-${old35Days.day.toString().padLeft(2, '0')}';
      final recentDate = '${recent10Days.year.toString().padLeft(4, '0')}-${recent10Days.month.toString().padLeft(2, '0')}-${recent10Days.day.toString().padLeft(2, '0')}';

      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 1,
        date: oldDate,
        notificationsReviewed: 10,
        actionsCompleted: 0,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 0,
      ));
      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 2,
        date: recentDate,
        notificationsReviewed: 5,
        actionsCompleted: 0,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 0,
      ));

      final notificationCutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final retentionCutoff = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;

      await db.runSetBasedCleanup(notificationCutoff, retentionCutoffTimestamp: retentionCutoff);

      // Verify Focus Sessions
      final focusSessions = await db.focusSessionDao.getAll();
      expect(focusSessions.length, equals(1));
      expect(focusSessions.first.id, equals(2));

      // Verify Daily Briefs
      final dailyBriefs = await db.dailyBriefDao.getAll();
      expect(dailyBriefs.length, equals(1));
      expect(dailyBriefs.first.date, equals(recentDate));
    });
  });
}
