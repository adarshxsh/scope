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

    test('insertNotification at 1,000 items automatically purges the oldest item', () async {
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      final initialEntries = List.generate(1000, (i) {
        return NotificationEntry(
          id: 'n-$i',
          packageName: 'com.test',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: baseTime + i,
          state: ReviewState.ACTIVE,
          priority: 'low',
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        );
      });

      await db.notificationDao.insertAll(initialEntries);
      expect(await db.notificationDao.getCount(), equals(1000));

      final newestEntry = NotificationEntry(
        id: 'n-1000',
        packageName: 'com.test',
        title: 'Title 1000',
        content: 'Content 1000',
        timestamp: baseTime + 1000,
        state: ReviewState.ACTIVE,
        priority: 'low',
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(newestEntry);

      expect(await db.notificationDao.getCount(), equals(1000));
      expect(await db.notificationDao.getById('n-0'), isNull);
      expect(await db.notificationDao.getById('n-1000'), isNotNull);
    });

    test('insertAll exceeding 1,000 items keeps only the newest 1,000 entries', () async {
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      final entries = List.generate(1050, (i) {
        return NotificationEntry(
          id: 'batch-$i',
          packageName: 'com.test',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: baseTime + i,
          state: ReviewState.ACTIVE,
          priority: 'low',
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        );
      });

      await db.notificationDao.insertAll(entries);

      expect(await db.notificationDao.getCount(), equals(1000));
      expect(await db.notificationDao.getById('batch-0'), isNull);
      expect(await db.notificationDao.getById('batch-49'), isNull);
      expect(await db.notificationDao.getById('batch-50'), isNotNull);
      expect(await db.notificationDao.getById('batch-1049'), isNotNull);
    });

    test('Purging notifications atomically deletes orphaned review queue items', () async {
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      final initialEntries = List.generate(1000, (i) {
        return NotificationEntry(
          id: 'q-$i',
          packageName: 'com.test',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: baseTime + i,
          state: ReviewState.ACTIVE,
          priority: 'low',
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        );
      });

      await db.notificationDao.insertAll(initialEntries);

      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 100,
        notificationId: 'q-0',
        priority: 'low',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      expect((await db.reviewQueueDao.getAll()).length, equals(1));

      final newestEntry = NotificationEntry(
        id: 'q-1000',
        packageName: 'com.test',
        title: 'Title 1000',
        content: 'Content 1000',
        timestamp: baseTime + 1000,
        state: ReviewState.ACTIVE,
        priority: 'low',
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(newestEntry);

      expect(await db.notificationDao.getById('q-0'), isNull);
      expect(await db.reviewQueueDao.getAll(), isEmpty);
    });

    test('FIFO purging preserves active unreviewed high-priority notifications', () async {
      final baseTime = DateTime.now().millisecondsSinceEpoch;

      final n1 = NotificationEntry(
        id: 'n-protected-high',
        packageName: 'com.test',
        title: 'High Priority',
        content: 'Important',
        timestamp: baseTime + 10,
        state: ReviewState.ACTIVE,
        priority: 'high',
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      final n2 = NotificationEntry(
        id: 'n-unprotected-low-old',
        packageName: 'com.test',
        title: 'Low Priority',
        content: 'Casual',
        timestamp: baseTime + 20,
        state: ReviewState.ACTIVE,
        priority: 'low',
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      final n3 = NotificationEntry(
        id: 'n-unprotected-reviewed',
        packageName: 'com.test',
        title: 'Reviewed High Priority',
        content: 'Done',
        timestamp: baseTime + 30,
        state: ReviewState.REVIEWED,
        priority: 'high',
        reviewed: true,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertAll([n1, n2, n3], maxCapacity: 2);

      expect(await db.notificationDao.getCount(), equals(2));
      expect(await db.notificationDao.getById('n-protected-high'), isNotNull);
      expect(await db.notificationDao.getById('n-unprotected-low-old'), isNull);
      expect(await db.notificationDao.getById('n-unprotected-reviewed'), isNotNull);
    });
  });
}
