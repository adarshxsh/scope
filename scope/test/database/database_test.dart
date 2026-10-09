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

    test('NotificationDao capacity limit enforcement and eviction tier order', () async {
      final now = DateTime.now();

      // n1: Inactive (reviewed = true), timestamp 100
      final n1 = NotificationEntry(
        id: 'n1',
        packageName: 'app',
        title: 'n1',
        content: 'n1',
        timestamp: 100,
        state: ReviewState.REVIEWED,
        reviewed: true,
        dismissed: false,
        priority: 'medium',
        isOngoing: false,
        createdAt: now,
      );

      // n2: Non-critical, timestamp 200
      final n2 = NotificationEntry(
        id: 'n2',
        packageName: 'app',
        title: 'n2',
        content: 'n2',
        timestamp: 200,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        priority: 'low',
        isOngoing: false,
        createdAt: now,
      );

      // n3: Non-critical, timestamp 300
      final n3 = NotificationEntry(
        id: 'n3',
        packageName: 'app',
        title: 'n3',
        content: 'n3',
        timestamp: 300,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        priority: 'medium',
        isOngoing: false,
        createdAt: now,
      );

      // n4: Critical priority, timestamp 50 (older timestamp)
      final n4 = NotificationEntry(
        id: 'n4',
        packageName: 'app',
        title: 'n4',
        content: 'n4',
        timestamp: 50,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        priority: 'critical',
        isOngoing: false,
        createdAt: now,
      );

      // Insert first 4 items with maxLimit 3
      await db.notificationDao.insertNotification(n1, maxLimit: 3);
      await db.notificationDao.insertNotification(n2, maxLimit: 3);
      await db.notificationDao.insertNotification(n3, maxLimit: 3);
      await db.notificationDao.insertNotification(n4, maxLimit: 3);

      var count = await db.notificationDao.getCount();
      expect(count, equals(3));

      // n1 (inactive) should be evicted first
      var fetched1 = await db.notificationDao.getById('n1');
      expect(fetched1, isNull);

      // n4 (critical) should be retained despite old timestamp (50)
      var fetched4 = await db.notificationDao.getById('n4');
      expect(fetched4, isNotNull);

      // n5: Critical priority, timestamp 400
      final n5 = NotificationEntry(
        id: 'n5',
        packageName: 'app',
        title: 'n5',
        content: 'n5',
        timestamp: 400,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        priority: 'critical',
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(n5, maxLimit: 3);

      count = await db.notificationDao.getCount();
      expect(count, equals(3));

      // n2 (non-critical, older timestamp 200) should be evicted next
      var fetched2 = await db.notificationDao.getById('n2');
      expect(fetched2, isNull);

      // Remaining items should be n3, n4, n5
      final remaining = await db.notificationDao.getAll();
      final remainingIds = remaining.map((e) => e.id).toSet();
      expect(remainingIds, equals({'n3', 'n4', 'n5'}));
    });

    test('NotificationDao deletes associated ReviewQueueTable entries atomically on eviction', () async {
      final now = DateTime.now();

      final n1 = NotificationEntry(
        id: 'n1',
        packageName: 'app',
        title: 'n1',
        content: 'n1',
        timestamp: 100,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        priority: 'low',
        isOngoing: false,
        createdAt: now,
      );

      final n2 = NotificationEntry(
        id: 'n2',
        packageName: 'app',
        title: 'n2',
        content: 'n2',
        timestamp: 200,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        priority: 'low',
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(n1, maxLimit: 1);
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 1,
        notificationId: 'n1',
        priority: 'low',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      ));

      // Inserting n2 with maxLimit 1 triggers eviction of n1 and its ReviewQueue item
      await db.notificationDao.insertNotification(n2, maxLimit: 1);

      final notifications = await db.notificationDao.getAll();
      expect(notifications.length, equals(1));
      expect(notifications.first.id, equals('n2'));

      final queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(0));
    });

    test('NotificationDao maintains capacity limit when inserting 6000 consecutive notifications', () async {
      final now = DateTime.now();
      final entries = List.generate(
        6000,
        (i) => NotificationEntry(
          id: 'n_$i',
          packageName: 'app',
          title: 'Notification $i',
          content: 'Content $i',
          timestamp: i,
          state: i % 10 == 0 ? ReviewState.ARCHIVED : ReviewState.ACTIVE,
          reviewed: i % 10 == 0,
          dismissed: false,
          priority: i % 5 == 0 ? 'critical' : 'medium',
          isOngoing: false,
          createdAt: now,
        ),
      );

      await db.notificationDao.insertAll(entries);

      final count = await db.notificationDao.getCount();
      expect(count, equals(5000));
    });
  });
}
