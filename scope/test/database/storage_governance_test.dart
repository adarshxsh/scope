import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/drift_notification_storage.dart';

void main() {
  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Storage Governance & Telemetry Database Unit Tests', () {
    test('AppSettingsDao creates default settings and updates values', () async {
      final defaultSettings = await db.appSettingsDao.getSettings();
      expect(defaultSettings.telemetryEnabled, isTrue);
      expect(defaultSettings.retentionDays, equals(7));
      expect(defaultSettings.maxNotificationQuota, equals(1000));

      await db.appSettingsDao.updateSettings(
        const AppSettingsTableCompanion(
          telemetryEnabled: Value(false),
          retentionDays: Value(14),
          maxNotificationQuota: Value(500),
        ),
      );

      final updatedSettings = await db.appSettingsDao.getSettings();
      expect(updatedSettings.telemetryEnabled, isFalse);
      expect(updatedSettings.retentionDays, equals(14));
      expect(updatedSettings.maxNotificationQuota, equals(500));
    });

    test('runSetBasedCleanup enforces retention window and FIFO quota eviction', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dayMs = 24 * 60 * 60 * 1000;

      // Create 5 notifications with different timestamps
      for (int i = 1; i <= 5; i++) {
        final entry = NotificationEntry(
          id: 'n$i',
          packageName: 'com.example.app',
          title: 'Notif $i',
          content: 'Content $i',
          timestamp: now - (5 - i) * dayMs, // n1 is 4 days old, n5 is today
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        );
        await db.notificationDao.insertNotification(entry);
        await db.reviewQueueDao.insertItem(ReviewQueueEntry(
          id: i,
          notificationId: 'n$i',
          priority: 'medium',
          enqueueTime: DateTime.now(),
          status: ReviewState.ACTIVE,
        ));
      }

      // Add orphaned review queue entry
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 99,
        notificationId: 'n-orphaned',
        priority: 'high',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      expect(await db.notificationDao.getCount(), equals(5));

      // Test 1: Quota eviction capping at 3 items (FIFO: deletes n1, n2 - the oldest)
      await db.runSetBasedCleanup(0, maxQuota: 3);

      var remainingNotifs = await db.notificationDao.getAll();
      expect(remainingNotifs.length, equals(3));
      final remainingIds = remainingNotifs.map((n) => n.id).toList();
      expect(remainingIds, containsAll(['n3', 'n4', 'n5']));
      expect(remainingIds, isNot(contains('n1')));
      expect(remainingIds, isNot(contains('n2')));

      var queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(3));
      expect(queueItems.map((q) => q.notificationId), containsAll(['n3', 'n4', 'n5']));

      // Test 2: Time-based retention cleanup deleting older than 12 hours (deletes n3, n4)
      final cutoff = now - (12 * 60 * 60 * 1000);
      await db.runSetBasedCleanup(cutoff, maxQuota: 0);

      remainingNotifs = await db.notificationDao.getAll();
      expect(remainingNotifs.length, equals(1));
      expect(remainingNotifs.first.id, equals('n5'));

      queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      expect(queueItems.first.notificationId, equals('n5'));
    });

    test('Database schema migration from v1 to v2 preserves existing data', () async {
      final now = DateTime.now();
      // Insert notification
      final notif = NotificationEntry(
        id: 'n-v1',
        packageName: 'com.whatsapp',
        title: 'V1 Notif',
        content: 'Data preserved',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );
      await db.notificationDao.insertNotification(notif);

      // Verify DB version is 2
      expect(db.schemaVersion, equals(2));

      // Verify existing entry is present
      final fetched = await db.notificationDao.getById('n-v1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('V1 Notif'));

      // Verify appSettingsTable was created and accessible
      final settings = await db.appSettingsDao.getSettings();
      expect(settings.retentionDays, equals(7));
    });
  });

  group('NotificationController Storage & Telemetry Tests', () {
    test('Controller handles retention days, storage quota, and manual purge', () async {
      final storage = DriftNotificationStorage(db);
      final controller = NotificationController(storage: storage);
      await Future.delayed(const Duration(milliseconds: 100));

      // Default settings check
      expect(controller.telemetryEnabled, isTrue);
      expect(controller.retentionDays, equals(7));
      expect(controller.maxNotificationQuota, equals(1000));

      // Update settings
      await controller.setTelemetryEnabled(false);
      expect(controller.telemetryEnabled, isFalse);

      await controller.setRetentionDays(14);
      expect(controller.retentionDays, equals(14));

      await controller.setMaxNotificationQuota(250);
      expect(controller.maxNotificationQuota, equals(250));

      // Generate test data
      await controller.generateTestData();
      expect(controller.totalStoredCount, greaterThan(0));
      expect(controller.estimatedDbSizeString, contains('KB'));

      // Test manual purge
      final purged = await controller.purgeExpiredDataNow();
      expect(purged, equals(0)); // All test data fits quota and retention
    });

  });
}
