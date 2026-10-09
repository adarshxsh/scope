import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_manager.dart';

class MockSecureStorage implements SecureStorageWrapper {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({required String key}) async => _storage[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async => _storage.remove(key);
}

void main() {
  group('SQLCipher Transparent Encryption Integration Tests', () {
    late Directory tempDir;
    late File dbFile;
    late MockSecureStorage mockStorage;
    late DatabaseKeyManager keyManager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sqlcipher_integration_test_');
      dbFile = File('${tempDir.path}/attention_os.db');
      mockStorage = MockSecureStorage();
      keyManager = DatabaseKeyManager(mockStorage);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('initializes attention_os.db encrypted with 256-bit key from secure storage', () async {
      final key = await keyManager.getOrCreateKey();

      final executor = NativeDatabase(
        dbFile,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$key';");
        },
      );

      final db = AttentionDatabase(executor);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'notif-1',
        packageName: 'com.whatsapp',
        title: 'Confidential Message',
        content: 'Your OTP is 123456',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      final fetched = await db.notificationDao.getById('notif-1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals('Your OTP is 123456'));

      await db.close();

      // Verify raw file on disk is encrypted and does NOT start with 'SQLite format 3'
      final rawBytes = await dbFile.readAsBytes();
      expect(rawBytes.length, greaterThan(0));
      final header = String.fromCharCodes(rawBytes.take(16));
      expect(header.startsWith('SQLite format 3'), isFalse);
    });

    test('all DAOs function correctly on encrypted database store', () async {
      final key = await keyManager.getOrCreateKey();
      final executor = NativeDatabase(
        dbFile,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$key';");
        },
      );
      final db = AttentionDatabase(executor);

      final now = DateTime.now();

      // 1. Notification DAO
      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'n1',
        packageName: 'com.slack',
        title: 'Project Update',
        content: 'Sprint planning tomorrow',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      // 2. Review Queue DAO
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 10,
        notificationId: 'n1',
        priority: 'high',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      ));

      // 3. Focus Session DAO
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 100,
        sessionStart: now,
        interruptions: 0,
        completion: false,
        duration: 0,
      ));

      // 4. Daily Brief DAO
      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 1000,
        date: '2026-09-22',
        notificationsReviewed: 10,
        actionsCompleted: 4,
        calendarEventsCreated: 2,
        remindersCreated: 1,
        archivedCount: 5,
      ));

      // Verify reads across all tables
      final notif = await db.notificationDao.getById('n1');
      expect(notif, isNotNull);
      expect(notif!.title, equals('Project Update'));

      final queue = await db.reviewQueueDao.getAll();
      expect(queue.length, equals(1));
      expect(queue.first.notificationId, equals('n1'));

      final activeSession = await db.focusSessionDao.getActiveSession();
      expect(activeSession, isNotNull);
      expect(activeSession!.id, equals(100));

      final brief = await db.dailyBriefDao.getBriefForDate('2026-09-22');
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, equals(10));

      // Test set-based cleanup transaction on encrypted store
      final cutoff = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
      await db.runSetBasedCleanup(cutoff);

      final remainingNotifs = await db.notificationDao.getAll();
      expect(remainingNotifs, isEmpty);

      final remainingQueue = await db.reviewQueueDao.getAll();
      expect(remainingQueue, isEmpty);

      await db.close();
    });

    test('re-opening database with correct key accesses data, wrong key fails', () async {
      final key = await keyManager.getOrCreateKey();

      // Write data with correct key
      var executor = NativeDatabase(
        dbFile,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$key';");
        },
      );
      var db = AttentionDatabase(executor);

      final now = DateTime.now();
      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'persisted-1',
        packageName: 'com.email',
        title: 'Secret Subject',
        content: 'Secret Body',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));
      await db.close();

      // Re-open with same correct key
      executor = NativeDatabase(
        dbFile,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$key';");
        },
      );
      db = AttentionDatabase(executor);
      final fetched = await db.notificationDao.getById('persisted-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Secret Subject'));
      await db.close();

      // Attempt to open with wrong key
      const wrongKey = 'badkey0000000000000000000000000000000000000000000000000000000000';
      executor = NativeDatabase(
        dbFile,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$wrongKey';");
        },
      );
      db = AttentionDatabase(executor);

      expect(
        () async => await db.notificationDao.getById('persisted-1'),
        throwsA(isA<SqliteException>()),
      );
      await db.close();
    });

    test('in-memory database works without requiring secure storage', () async {
      final inMemoryDb = AttentionDatabase.inMemory();

      final now = DateTime.now();
      await inMemoryDb.notificationDao.insertNotification(NotificationEntry(
        id: 'mem1',
        packageName: 'test',
        title: 'Memory Test',
        content: 'In-memory notification',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      final fetched = await inMemoryDb.notificationDao.getById('mem1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Memory Test'));

      await inMemoryDb.close();
    });
  });
}
