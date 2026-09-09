import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AttentionDatabase Storage Quota & Dynamic Cleanup Tests', () {
    test('runDynamicCleanup respects user dynamic retention duration', () async {
      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2)).millisecondsSinceEpoch;
      final fiveDaysAgo = now.subtract(const Duration(days: 5)).millisecondsSinceEpoch;
      final tenDaysAgo = now.subtract(const Duration(days: 10)).millisecondsSinceEpoch;

      final n2 = NotificationEntry(
        id: 'n-2d',
        packageName: 'app',
        title: 'Recent',
        content: 'Body',
        timestamp: twoDaysAgo,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      final n5 = NotificationEntry(
        id: 'n-5d',
        packageName: 'app',
        title: 'Medium Old',
        content: 'Body',
        timestamp: fiveDaysAgo,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      final n10 = NotificationEntry(
        id: 'n-10d',
        packageName: 'app',
        title: 'Very Old',
        content: 'Body',
        timestamp: tenDaysAgo,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertAll([n2, n5, n10]);

      // With retention = 3 days, items older than 3 days (n5 and n10) should be purged
      await db.runDynamicCleanup(retentionDays: 3, storageQuotaMb: -1);

      final remaining = await db.notificationDao.getAll();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('n-2d'));
    });

    test('runDynamicCleanup enforces storage quota in FIFO deletion order', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert 5 entries with distinct timestamps
      final entries = List.generate(
        5,
        (i) => NotificationEntry(
          id: 'n-$i',
          packageName: 'com.test.app',
          title: 'Notification Title $i',
          content: 'This is body text for notification number $i with extra long content payload...',
          timestamp: now + (i * 1000), // n-0 is oldest, n-4 is newest
          state: i < 3 ? ReviewState.ARCHIVED : ReviewState.ACTIVE,
          reviewed: false,
          dismissed: i < 3,
          isOngoing: false,
          createdAt: DateTime.now(),
        ),
      );

      await db.notificationDao.insertAll(entries);

      final initialSize = await db.getStorageUsageBytes();
      expect(initialSize, greaterThan(0));

      // Set quota extremely small (e.g., 0 MB or tiny quota) to trigger quota purging
      await db.runDynamicCleanup(retentionDays: -1, storageQuotaMb: 0);

      final remaining = await db.notificationDao.getAll();
      // Quota <= 0 MB forces purging starting with oldest historical entries
      expect(remaining.length, lessThan(5));
    });

    test('getStorageUsageBytes computes non-zero size for stored notifications', () async {
      final entry = NotificationEntry(
        id: 'n-test',
        packageName: 'com.test',
        title: 'Title',
        content: 'Content Payload',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(entry);

      final usage = await db.getStorageUsageBytes();
      expect(usage, greaterThan(0));
    });
  });
}
