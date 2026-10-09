import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_migrator.dart';
import 'package:scope/database/secure_key_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SQLCipher Database Encryption & Secure Key Storage Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_encryption_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('SecureKeyStorage generates 256-bit (64-char hex) key and caches it', () async {
      final keyStorage = SecureKeyStorage();
      keyStorage.clearCacheForTesting();

      final key1 = await keyStorage.getOrCreatePassphrase();
      expect(key1, isNotEmpty);
      expect(key1.length, equals(64)); // 32 bytes hex encoded = 64 hex chars = 256 bits

      final key2 = await keyStorage.getOrCreatePassphrase();
      expect(key2, equals(key1)); // Cached key returned
    });

    test('Header inspection detects plaintext SQLite file vs non-plaintext', () async {
      final plaintextFile = File('${tempDir.path}/plain.db');
      final db = sqlite3.open(plaintextFile.path);
      db.execute('CREATE TABLE dummy (id INTEGER PRIMARY KEY, name TEXT);');
      db.execute("INSERT INTO dummy VALUES (1, 'test');");
      db.dispose();

      final isPlaintext = await DatabaseMigrator.isPlaintextSqlite(plaintextFile);
      expect(isPlaintext, isTrue);

      final nonPlaintextFile = File('${tempDir.path}/encrypted_mock.db');
      await nonPlaintextFile.writeAsBytes(List.filled(32, 0xFF)); // Ciphertext bytes
      final isNonPlaintext = await DatabaseMigrator.isPlaintextSqlite(nonPlaintextFile);
      expect(isNonPlaintext, isFalse);

      final nonExistentFile = File('${tempDir.path}/nonexistent.db');
      final isNonExistentPlaintext = await DatabaseMigrator.isPlaintextSqlite(nonExistentFile);
      expect(isNonExistentPlaintext, isFalse);
    });

    test('Encrypted SQLCipher database configuration executes writes and reads', () async {
      final dbFile = File('${tempDir.path}/encrypted_attention_os.db');
      final keyStorage = SecureKeyStorage();
      keyStorage.setPassphraseForTesting('a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef');
      final passphrase = await keyStorage.getOrCreatePassphrase();

      final db = AttentionDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$passphrase';");
          },
        ),
      );

      // Perform write operation to create and flush database page
      await db.into(db.notificationsTable).insert(
            NotificationsTableCompanion.insert(
              id: 'notif_100',
              packageName: 'com.example.test',
              title: 'Secret Message',
              content: 'Sensitive content that must be encrypted',
              timestamp: 1620000000,
              state: ReviewState.ACTIVE,
            ),
          );

      final saved = await (db.select(db.notificationsTable)..where((t) => t.id.equals('notif_100'))).getSingle();
      expect(saved.title, equals('Secret Message'));

      await db.close();
      expect(await dbFile.exists(), isTrue);
    });

    test('Legacy plaintext database migration executes atomically with 100% row preservation', () async {
      final targetFile = File('${tempDir.path}/attention_os.db');

      // 1. Create legacy plaintext SQLite database file
      final legacyDb = sqlite3.open(targetFile.path);

      legacyDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT NOT NULL PRIMARY KEY,
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

      legacyDb.execute('''
        CREATE TABLE review_queue_table (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          notification_id TEXT NOT NULL,
          priority TEXT NOT NULL,
          enqueue_time INTEGER NOT NULL,
          expiry_time INTEGER,
          status TEXT NOT NULL
        );
      ''');

      legacyDb.execute('''
        CREATE TABLE focus_sessions_table (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          session_start INTEGER NOT NULL,
          session_end INTEGER,
          interruptions INTEGER NOT NULL DEFAULT 0,
          completion INTEGER NOT NULL DEFAULT 0,
          duration INTEGER NOT NULL
        );
      ''');

      legacyDb.execute('''
        CREATE TABLE daily_brief_table (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL UNIQUE,
          notifications_reviewed INTEGER NOT NULL DEFAULT 0,
          actions_completed INTEGER NOT NULL DEFAULT 0,
          calendar_events_created INTEGER NOT NULL DEFAULT 0,
          reminders_created INTEGER NOT NULL DEFAULT 0,
          archived_count INTEGER NOT NULL DEFAULT 0
        );
      ''');

      // Insert test records across all tables
      legacyDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, created_at)
        VALUES ('notif_1', 'com.whatsapp', 'Bank OTP', 'Your code is 492018', 1700000000, 'ACTIVE', 1700000000),
               ('notif_2', 'com.google.android.gm', 'Meeting', 'Standup in 10m', 1700000100, 'ACTIVE', 1700000100);
      ''');

      legacyDb.execute('''
        INSERT INTO review_queue_table (notification_id, priority, enqueue_time, status)
        VALUES ('notif_1', 'critical', 1700000000, 'ACTIVE'),
               ('notif_2', 'high', 1700000100, 'ACTIVE');
      ''');

      legacyDb.execute('''
        INSERT INTO focus_sessions_table (session_start, session_end, interruptions, completion, duration)
        VALUES (1700000000, 1700001800, 1, 1, 1800);
      ''');

      legacyDb.execute('''
        INSERT INTO daily_brief_table (date, notifications_reviewed, actions_completed, calendar_events_created, reminders_created, archived_count)
        VALUES ('2026-09-09', 15, 3, 1, 2, 10);
      ''');

      legacyDb.dispose();

      // Verify file is plaintext SQLite before migration
      expect(await DatabaseMigrator.isPlaintextSqlite(targetFile), isTrue);

      // 2. Perform migration to encrypted SQLCipher database
      const testPassphrase = '3f8a9b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a';

      await DatabaseMigrator.migratePlaintextToEncrypted(
        targetDbFile: targetFile,
        passphrase: testPassphrase,
      );

      // 3. Open migrated database using AttentionDatabase with passphrase and verify row contents
      final db = AttentionDatabase(
        NativeDatabase(
          targetFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$testPassphrase';");
          },
        ),
      );

      final notifications = await db.select(db.notificationsTable).get();
      expect(notifications.length, equals(2));
      expect(notifications.first.title, equals('Bank OTP'));
      expect(notifications.last.title, equals('Meeting'));

      final reviewQueue = await db.select(db.reviewQueueTable).get();
      expect(reviewQueue.length, equals(2));
      expect(reviewQueue.first.priority, equals('critical'));

      final focusSessions = await db.select(db.focusSessionsTable).get();
      expect(focusSessions.length, equals(1));
      expect(focusSessions.first.duration, equals(1800));

      final dailyBriefs = await db.select(db.dailyBriefTable).get();
      expect(dailyBriefs.length, equals(1));
      expect(dailyBriefs.first.date, equals('2026-09-09'));

      await db.close();

      // Ensure legacy plaintext temp file was deleted
      final legacyFile = File('${targetFile.parent.path}/attention_os_legacy.db');
      expect(await legacyFile.exists(), isFalse);
    });

    test('Database read/write latency on encrypted SQLCipher is under performance thresholds', () async {
      final dbFile = File('${tempDir.path}/perf_test.db');
      const testPassphrase = 'perf_test_key_1234567890abcdef1234567890abcdef1234567890abcdef';

      final stopwatch = Stopwatch()..start();

      final db = AttentionDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$testPassphrase';");
          },
        ),
      );

      // Perform batch inserts
      await db.batch((batch) {
        for (int i = 0; i < 50; i++) {
          batch.insert(
            db.notificationsTable,
            NotificationsTableCompanion.insert(
              id: 'perf_$i',
              packageName: 'com.test.perf',
              title: 'Test Notification $i',
              content: 'Content for latency measurement $i',
              timestamp: 1700000000 + i,
              state: ReviewState.ACTIVE,
            ),
          );
        }
      });

      final queryResults = await db.select(db.notificationsTable).get();
      stopwatch.stop();

      expect(queryResults.length, equals(50));
      // Database operation including setup and 50 writes + reads completes within 500ms
      expect(stopwatch.elapsedMilliseconds, lessThan(500));

      await db.close();
    });
  });
}
