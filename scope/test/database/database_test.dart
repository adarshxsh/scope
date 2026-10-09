import 'dart:io';
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

    test('runSetBasedCleanup enforces maxRows cap with EXPIRED -> ARCHIVED -> REVIEWED priority order', () async {
      final now = DateTime.now();

      // Insert 2 ACTIVE items
      for (int i = 1; i <= 2; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'active-$i',
          packageName: 'com.example',
          title: 'Active $i',
          content: 'Content',
          timestamp: now.millisecondsSinceEpoch + i,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ));
      }

      // Insert 2 REVIEWED items
      for (int i = 1; i <= 2; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'reviewed-$i',
          packageName: 'com.example',
          title: 'Reviewed $i',
          content: 'Content',
          timestamp: now.millisecondsSinceEpoch + 10 + i,
          state: ReviewState.REVIEWED,
          reviewed: true,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ));
      }

      // Insert 2 ARCHIVED items
      for (int i = 1; i <= 2; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'archived-$i',
          packageName: 'com.example',
          title: 'Archived $i',
          content: 'Content',
          timestamp: now.millisecondsSinceEpoch + 20 + i,
          state: ReviewState.ARCHIVED,
          reviewed: false,
          dismissed: true,
          isOngoing: false,
          createdAt: now,
        ));
      }

      // Insert 2 EXPIRED items
      for (int i = 1; i <= 2; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'expired-$i',
          packageName: 'com.example',
          title: 'Expired $i',
          content: 'Content',
          timestamp: now.millisecondsSinceEpoch + 30 + i,
          state: ReviewState.EXPIRED,
          reviewed: false,
          dismissed: true,
          isOngoing: false,
          createdAt: now,
        ));
      }

      // Total 8 items. Cap at maxRows = 5.
      // Need to delete 3 excess items.
      // Priority: EXPIRED first (2 items), then ARCHIVED (1 item).
      final cutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      await db.runSetBasedCleanup(cutoff, maxRows: 5, compact: false);

      final remaining = await db.notificationDao.getAll();
      expect(remaining.length, equals(5));

      final remainingIds = remaining.map((e) => e.id).toSet();
      // Expired items should both be deleted
      expect(remainingIds.contains('expired-1'), isFalse);
      expect(remainingIds.contains('expired-2'), isFalse);
      // Archived 1 should be deleted (oldest archived)
      expect(remainingIds.contains('archived-1'), isFalse);
      // Archived 2, Reviewed 1 & 2, Active 1 & 2 should remain
      expect(remainingIds.contains('archived-2'), isTrue);
      expect(remainingIds.contains('active-1'), isTrue);
      expect(remainingIds.contains('active-2'), isTrue);
      expect(remainingIds.contains('reviewed-1'), isTrue);
      expect(remainingIds.contains('reviewed-2'), isTrue);
    });

    test('runSetBasedCleanup preserves active notifications even when exceeding maxRows cap', () async {
      final now = DateTime.now();

      // Insert 10 ACTIVE items
      for (int i = 1; i <= 10; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'active-$i',
          packageName: 'com.example',
          title: 'Active $i',
          content: 'Content',
          timestamp: now.millisecondsSinceEpoch + i,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ));
      }

      final cutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      // Cap at maxRows = 5, but all 10 are active and within age cutoff
      await db.runSetBasedCleanup(cutoff, maxRows: 5, compact: false);

      final remaining = await db.notificationDao.getAll();
      // All 10 active items must be preserved according to constraint
      expect(remaining.length, equals(10));
    });

    test('SQLite VACUUM compaction decreases file size on disk after batch deletions', () async {
      final tempDir = Directory.systemTemp.createTempSync('drift_test_');
      final dbFile = File('${tempDir.path}/test_attention.db');

      final diskDb = AttentionDatabase(NativeDatabase(dbFile));
      final now = DateTime.now();
      final largePayload = 'A' * 2000; // 2 KB string payload per row

      // Insert 300 expired rows to expand disk file size
      for (int i = 0; i < 300; i++) {
        await diskDb.notificationDao.insertNotification(NotificationEntry(
          id: 'payload-$i',
          packageName: 'com.example.large',
          title: 'Large Payload Item $i',
          content: largePayload,
          timestamp: now.millisecondsSinceEpoch + i,
          state: ReviewState.EXPIRED,
          reviewed: false,
          dismissed: true,
          isOngoing: false,
          createdAt: now,
        ));
      }

      final sizeBeforeCleanup = dbFile.lengthSync();
      expect(sizeBeforeCleanup, greaterThan(0));

      final cutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      // Run cleanup with maxRows = 10 and compaction
      await diskDb.runSetBasedCleanup(cutoff, maxRows: 10, compact: true);

      final sizeAfterCompaction = dbFile.lengthSync();
      final countAfter = await diskDb.notificationDao.getCount();

      expect(countAfter, equals(10));
      expect(sizeAfterCompaction, lessThan(sizeBeforeCleanup));

      await diskDb.close();
      tempDir.deleteSync(recursive: true);
    });
  });
}
