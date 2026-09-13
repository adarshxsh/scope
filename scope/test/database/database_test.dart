import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';

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

    test('NotificationDao enforces maxCapacity cap on single insertNotification', () async {
      db.notificationDao.maxCapacity = 5;
      final now = DateTime.now();

      for (int i = 1; i <= 10; i++) {
        await db.notificationDao.insertNotification(
          NotificationEntry(
            id: 'n-$i',
            packageName: 'com.example.app',
            title: 'Title $i',
            content: 'Body $i',
            timestamp: now.millisecondsSinceEpoch + i * 1000,
            state: ReviewState.EXPIRED,
            reviewed: false,
            dismissed: true,
            isOngoing: false,
            createdAt: now,
          ),
        );
      }

      final count = await db.notificationDao.getCount();
      expect(count, equals(5));

      final all = await db.notificationDao.getAll();
      expect(all.length, equals(5));
      // Newest entries (6 to 10) should be preserved
      final ids = all.map((e) => e.id).toSet();
      expect(ids, equals({'n-6', 'n-7', 'n-8', 'n-9', 'n-10'}));
    });

    test('NotificationDao enforces maxCapacity cap on batch insertAll', () async {
      db.notificationDao.maxCapacity = 5;
      final now = DateTime.now();

      final entries = List.generate(
        10,
        (i) => NotificationEntry(
          id: 'batch-$i',
          packageName: 'com.example.app',
          title: 'Title $i',
          content: 'Body $i',
          timestamp: now.millisecondsSinceEpoch + i * 1000,
          state: ReviewState.EXPIRED,
          reviewed: false,
          dismissed: true,
          isOngoing: false,
          createdAt: now,
        ),
      );

      await db.notificationDao.insertAll(entries);

      final count = await db.notificationDao.getCount();
      expect(count, equals(5));

      final all = await db.notificationDao.getAll();
      final ids = all.map((e) => e.id).toSet();
      expect(ids, equals({'batch-5', 'batch-6', 'batch-7', 'batch-8', 'batch-9'}));
    });

    test('NotificationDao preserves active review queue entries over dismissed entries during pruning', () async {
      db.notificationDao.maxCapacity = 3;
      final now = DateTime.now();

      // n-1: Oldest timestamp, EXPIRED (non-active)
      final n1 = NotificationEntry(
        id: 'n-1',
        packageName: 'com.example',
        title: 'T1',
        content: 'C1',
        timestamp: 1000,
        state: ReviewState.EXPIRED,
        reviewed: false,
        dismissed: true,
        isOngoing: false,
        createdAt: now,
      );

      // n-2: Older timestamp, ACTIVE
      final n2 = NotificationEntry(
        id: 'n-2',
        packageName: 'com.example',
        title: 'T2',
        content: 'C2',
        timestamp: 2000,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      // n-3: Newer timestamp, EXPIRED
      final n3 = NotificationEntry(
        id: 'n-3',
        packageName: 'com.example',
        title: 'T3',
        content: 'C3',
        timestamp: 3000,
        state: ReviewState.EXPIRED,
        reviewed: false,
        dismissed: true,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(n1);
      await db.notificationDao.insertNotification(n2);
      await db.notificationDao.insertNotification(n3);

      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 1,
        notificationId: 'n-1',
        priority: 'high',
        enqueueTime: now,
        status: ReviewState.EXPIRED,
      ));
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 2,
        notificationId: 'n-2',
        priority: 'high',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      ));

      // Insert 4th item (EXPIRED), breaching capacity limit (3)
      final n4 = NotificationEntry(
        id: 'n-4',
        packageName: 'com.example',
        title: 'T4',
        content: 'C4',
        timestamp: 4000,
        state: ReviewState.EXPIRED,
        reviewed: false,
        dismissed: true,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(n4);

      final count = await db.notificationDao.getCount();
      expect(count, equals(3));

      final all = await db.notificationDao.getAll();
      final ids = all.map((e) => e.id).toSet();
      // n-1 (EXPIRED, oldest) should be pruned.
      // n-2 (ACTIVE) must be preserved despite being older than n-3 and n-4!
      expect(ids, equals({'n-2', 'n-3', 'n-4'}));

      // Verify ReviewQueueTable orphaned record for n-1 was cleanly removed
      final queueItems = await db.reviewQueueDao.getAll();
      final queueIds = queueItems.map((e) => e.notificationId).toSet();
      expect(queueIds, equals({'n-2'}));
    });

    test('DriftNotificationStorage payload verification boundaries and length caps', () async {
      final storage = DriftNotificationStorage(db);
      final hugeTitle = 'A' * 2000;
      final hugeContent = 'B' * 20000;

      final notif = AppNotification(
        id: '   ',
        packageName: 'com.example.boundary',
        title: hugeTitle,
        content: hugeContent,
        timestamp: -100,
        state: ReviewState.ACTIVE,
      );

      await storage.save(notif);

      final all = await storage.getAll();
      expect(all.length, equals(1));
      final saved = all.first;
      expect(saved.id.isNotEmpty, isTrue);
      expect(saved.title.length, equals(1000));
      expect(saved.content.length, equals(10000));
      expect(saved.timestamp, greaterThan(0));
    });

    test('compact runs VACUUM without throwing', () async {
      expect(() async => await db.compact(), returnsNormally);
    });
  });
}
