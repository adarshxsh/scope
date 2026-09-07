import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_migrator.dart';
import 'package:scope/database/secure_key_storage.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DatabaseKeyManager Tests', () {
    test('generates and returns a 256-bit (64 hex character) key', () async {
      final keyManager = DatabaseKeyManager(testKey: 'a' * 64);
      final key = await keyManager.getOrCreateKey();
      expect(key, hasLength(64));
      expect(key, equals('a' * 64));
    });

    test('fallback key is 256 bits (64 hex characters) in test environment', () async {
      final keyManager = DatabaseKeyManager();
      final key = await keyManager.getOrCreateKey();
      expect(key, hasLength(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });
  });

  group('SQLCipher Encryption at Rest Tests', () {
    test('database file created with key cannot be opened without authentication', () async {
      final dbFile = File('${tempDir.path}/encrypted_test.db');
      final encryptionKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

      // 1. Create and populate encrypted database
      final encDb = AttentionDatabase.encrypted(encryptionKey, file: dbFile);
      final now = DateTime.now();

      await encDb.notificationDao.insertNotification(
        NotificationEntry(
          id: 'enc-1',
          packageName: 'com.secret.bank',
          title: 'Financial Alert',
          content: 'Account debited \$500',
          timestamp: now.millisecondsSinceEpoch,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ),
      );

      await encDb.close();
      expect(dbFile.existsSync(), isTrue);

      // 2. Unauthenticated raw sqlite3 open without key must fail to read
      final rawDb = sqlite3.open(dbFile.path);
      expect(
        () => rawDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      rawDb.close();

      // 3. Authenticated raw sqlite3 open with key succeeds
      final authenticatedDb = sqlite3.open(dbFile.path);
      authenticatedDb.execute("PRAGMA key = '$encryptionKey';");
      final rows = authenticatedDb.select('SELECT * FROM notifications_table;');
      expect(rows, hasLength(1));
      expect(rows.first['title'], equals('Financial Alert'));
      expect(rows.first['content'], equals('Account debited \$500'));
      authenticatedDb.close();

      // 4. Opening via AttentionDatabase.encrypted succeeds
      final encDb2 = AttentionDatabase.encrypted(encryptionKey, file: dbFile);
      final fetched = await encDb2.notificationDao.getById('enc-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Financial Alert'));
      await encDb2.close();
    });
  });

  group('Legacy Cleartext Migration Tests', () {
    test('detects cleartext database, migrates all rows, and purges cleartext file', () async {
      final dbFile = File('${tempDir.path}/attention_os.db');
      final encryptionKey = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

      // 1. Create legacy unencrypted cleartext database
      final cleartextDb = sqlite3.open(dbFile.path);
      cleartextDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT PRIMARY KEY NOT NULL,
          package_name TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          category TEXT,
          is_ongoing INTEGER NOT NULL DEFAULT 0,
          priority TEXT,
          priority_score REAL,
          classified_category TEXT,
          explanation TEXT,
          latency_ms INTEGER,
          rule_version TEXT,
          model_version TEXT,
          engine_version TEXT,
          extracted_features TEXT,
          state TEXT NOT NULL,
          snoozed_until INTEGER,
          last_updated INTEGER,
          policy_score REAL,
          final_score REAL,
          reviewed INTEGER NOT NULL DEFAULT 0,
          dismissed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''');

      cleartextDb.execute('''
        CREATE TABLE review_queue_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          notification_id TEXT NOT NULL,
          priority TEXT NOT NULL,
          enqueue_time INTEGER NOT NULL,
          expiry_time INTEGER,
          status TEXT NOT NULL
        );
      ''');

      cleartextDb.execute('''
        CREATE TABLE daily_brief_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          date TEXT NOT NULL UNIQUE,
          notifications_reviewed INTEGER NOT NULL DEFAULT 0,
          actions_completed INTEGER NOT NULL DEFAULT 0,
          calendar_events_created INTEGER NOT NULL DEFAULT 0,
          reminders_created INTEGER NOT NULL DEFAULT 0,
          archived_count INTEGER NOT NULL DEFAULT 0
        );
      ''');

      // Insert cleartext legacy rows
      cleartextDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, created_at)
        VALUES ('legacy-1', 'com.whatsapp', 'Legacy Title', 'Legacy Content', 1700000000, 'ACTIVE', 1700000000);
      ''');

      cleartextDb.execute('''
        INSERT INTO review_queue_table (id, notification_id, priority, enqueue_time, status)
        VALUES (10, 'legacy-1', 'high', 1700000000, 'ACTIVE');
      ''');

      cleartextDb.execute('''
        INSERT INTO daily_brief_table (id, date, notifications_reviewed, actions_completed)
        VALUES (1, '2026-09-07', 42, 12);
      ''');

      cleartextDb.close();

      // 2. Verify file is detected as unencrypted cleartext
      expect(DatabaseMigrator.isUnencryptedCleartext(dbFile), isTrue);

      // 3. Initialize encrypted AttentionDatabase (triggers inline migration)
      final encryptedDb = AttentionDatabase.encrypted(encryptionKey, file: dbFile);

      // 4. Verify migrated notification history and telemetry
      final notification = await encryptedDb.notificationDao.getById('legacy-1');
      expect(notification, isNotNull);
      expect(notification!.title, equals('Legacy Title'));
      expect(notification.content, equals('Legacy Content'));

      final queueItems = await encryptedDb.reviewQueueDao.getAll();
      expect(queueItems, hasLength(1));
      expect(queueItems.first.notificationId, equals('legacy-1'));

      final brief = await encryptedDb.dailyBriefDao.getBriefForDate('2026-09-07');
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, equals(42));
      expect(brief.actionsCompleted, equals(12));

      await encryptedDb.close();

      // 5. Verify original legacy cleartext backup files are completely purged
      expect(File('${dbFile.path}.legacy').existsSync(), isFalse);

      // 6. Verify dbFile is now encrypted and cannot be read without key
      final unauthDb = sqlite3.open(dbFile.path);
      expect(
        () => unauthDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      unauthDb.close();

      // 7. Verify file is no longer reported as unencrypted
      expect(DatabaseMigrator.isUnencryptedCleartext(dbFile), isFalse);
    });
  });
}
