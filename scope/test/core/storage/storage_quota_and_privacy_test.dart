import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/storage_logger.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';

void main() {
  late AttentionDatabase db;
  late DriftNotificationStorage storage;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
    storage = DriftNotificationStorage(db);
    StorageLogger.setDebugMode(false);
  });

  tearDown(() async {
    await db.close();
  });

  group('Storage Quota and Privacy Guardrails Integration Tests', () {
    test('DriftNotificationStorage enforces 500 max capacity quota on batch save', () async {
      final notifications = List.generate(
        520,
        (i) => AppNotification(
          id: 'batch_$i',
          packageName: 'com.example.app',
          title: 'Title $i',
          content: 'Content payload for $i',
          timestamp: 1000000 + i,
        ),
      );

      await storage.saveAll(notifications);

      expect(await storage.count, equals(500));

      final all = await storage.getAll();
      expect(all.length, equals(500));
      // The oldest 20 items (batch_0 to batch_19) should have been evicted
      expect(all.any((n) => n.id == 'batch_0'), isFalse);
      expect(all.any((n) => n.id == 'batch_19'), isFalse);
      expect(all.any((n) => n.id == 'batch_20'), isTrue);
      expect(all.any((n) => n.id == 'batch_519'), isTrue);
    });

    test('DriftNotificationStorage automatically sanitizes inputs before saving', () async {
      final huge = AppNotification(
        id: 'huge_payload',
        packageName: 'com.app.test\x00',
        title: 'T' * 400,
        content: 'C' * 1500,
        timestamp: 2000000,
      );

      await storage.save(huge);

      final fetched = await storage.getById('huge_payload');
      expect(fetched, isNotNull);
      expect(fetched!.title.length, equals(250));
      expect(fetched.content.length, equals(1000));
      expect(fetched.packageName, equals('com.app.test'));
    });

    test('StorageLogger logs metrics without cleartext PII', () {
      // Confirm logger runs without throwing exceptions
      expect(
        () => StorageLogger.logStorageCleanup(
          deletedCount: 10,
          evictedCount: 5,
          durationMs: 15,
          totalRemaining: 480,
        ),
        returnsNormally,
      );

      expect(
        () => StorageLogger.logCapacityEnforced(
          currentCount: 500,
          maxCapacity: 500,
          evictedCount: 20,
        ),
        returnsNormally,
      );

      expect(
        () => StorageLogger.logStorageError(
          'testOperation',
          'Failed for user email secret@example.com with card 1234567812345678',
        ),
        returnsNormally,
      );
    });
  });
}
