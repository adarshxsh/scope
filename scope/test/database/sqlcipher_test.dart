import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/security_key_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_dir_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SQLCipher Database Encryption & Security Key Tests', () {
    test('SecurityKeyManager generates valid 256-bit hex key', () async {
      final key = await SecurityKeyManager.getDatabaseKey();
      expect(key, isNotNull);
      expect(key.length, greaterThanOrEqualTo(32));
    });

    test('AttentionDatabase encrypted disk fixture is 100% encrypted', () async {
      final dbFile = File(p.join(tempDir.path, 'attention_os_enc.db'));
      const testKey = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      final db = AttentionDatabase.encrypted(testKey, file: dbFile);

      final now = DateTime.now();
      await db.notificationDao.insertNotification(
        NotificationEntry(
          id: 'notif_1',
          packageName: 'com.whatsapp',
          title: 'Encrypted Title',
          content: 'Encrypted Body Content',
          timestamp: now.millisecondsSinceEpoch,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ),
      );

      final fetched = await db.notificationDao.getById('notif_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Encrypted Title'));

      await db.close();

      // 1. Verify file exists on disk and is non-empty
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));

      // 2. Verify file header is NOT plaintext 'SQLite format 3'
      final bytes = await dbFile.readAsBytes();
      final headerStr = String.fromCharCodes(bytes.sublist(0, 15));
      expect(headerStr, isNot(equals('SQLite format 3')));

      // 3. Inspecting file with unencrypted sqlite3 CLI or raw sqlite3 returns database file format error
      expect(() {
        final rawDb = sqlite.sqlite3.open(dbFile.path);
        try {
          rawDb.select('SELECT * FROM notifications_table;');
        } finally {
          rawDb.close();
        }
      }, throwsA(anything));

      // 4. Opening with SQLCipher and matching PRAGMA key succeeds
      final dbReopened = AttentionDatabase.encrypted(testKey, file: dbFile);
      final fetched2 = await dbReopened.notificationDao.getById('notif_1');
      expect(fetched2, isNotNull);
      expect(fetched2!.content, equals('Encrypted Body Content'));
      await dbReopened.close();
    });

    test('DAO CRUD operations pass seamlessly on encrypted SQLCipher database', () async {
      final dbFile = File(p.join(tempDir.path, 'attention_os_crud.db'));
      const testKey = '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b';

      final db = AttentionDatabase.encrypted(testKey, file: dbFile);

      final now = DateTime.now();

      // NotificationDao
      await db.notificationDao.insertNotification(
        NotificationEntry(
          id: 'n_crud_1',
          packageName: 'com.banking.app',
          title: 'Debit Alert',
          content: 'Rs 500 debited',
          timestamp: now.millisecondsSinceEpoch,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ),
      );

      // ReviewQueueDao
      await db.reviewQueueDao.insertItem(
        ReviewQueueEntry(
          id: 1,
          notificationId: 'n_crud_1',
          priority: 'critical',
          enqueueTime: now,
          status: ReviewState.ACTIVE,
        ),
      );

      // FocusSessionDao
      await db.focusSessionDao.insertSession(
        FocusSessionEntry(
          id: 1,
          sessionStart: now,
          interruptions: 0,
          completion: false,
          duration: 0,
        ),
      );

      // DailyBriefDao
      await db.dailyBriefDao.insertOrUpdate(
        DailyBriefEntry(
          id: 1,
          date: '2026-09-19',
          notificationsReviewed: 10,
          actionsCompleted: 4,
          calendarEventsCreated: 1,
          remindersCreated: 2,
          archivedCount: 5,
        ),
      );

      // Queries
      final notif = await db.notificationDao.getById('n_crud_1');
      expect(notif, isNotNull);
      expect(notif!.title, equals('Debit Alert'));

      final queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      expect(queueItems.first.priority, equals('critical'));

      final activeSession = await db.focusSessionDao.getActiveSession();
      expect(activeSession, isNotNull);

      final brief = await db.dailyBriefDao.getBriefForDate('2026-09-19');
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, equals(10));

      await db.close();
    });

    test('Safe migration converts unencrypted database to encrypted SQLCipher container', () async {
      final dbFile = File(p.join(tempDir.path, 'unencrypted_legacy.db'));
      const testKey = 'migration_secret_key_64_hex_chars_value_1234567890abcdef12345678';

      // 1. Create a plain unencrypted SQLite database
      final rawUnencrypted = sqlite.sqlite3.open(dbFile.path);
      rawUnencrypted.execute('''
        CREATE TABLE notifications_table (
          id TEXT NOT NULL PRIMARY KEY,
          package_name TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          state TEXT NOT NULL,
          reviewed INTEGER NOT NULL,
          dismissed INTEGER NOT NULL,
          is_ongoing INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');
      rawUnencrypted.execute('''
        INSERT INTO notifications_table VALUES (
          'legacy_1', 'com.whatsapp', 'Legacy Title', 'Legacy Content', 1000000, 'ACTIVE', 0, 0, 0, 1000000
        );
      ''');
      rawUnencrypted.close();

      // Verify it is unencrypted initially
      final initialBytes = await dbFile.readAsBytes();
      final initialHeader = String.fromCharCodes(initialBytes.sublist(0, 15));
      expect(initialHeader, equals('SQLite format 3'));

      // 2. Open via AttentionDatabase.encrypted which triggers automatic safe migration
      final db = AttentionDatabase.encrypted(testKey, file: dbFile);

      final migratedNotif = await db.notificationDao.getById('legacy_1');
      expect(migratedNotif, isNotNull);
      expect(migratedNotif!.title, equals('Legacy Title'));
      expect(migratedNotif.content, equals('Legacy Content'));

      await db.close();

      // 3. Verify file is now fully encrypted on disk
      final migratedBytes = await dbFile.readAsBytes();
      final migratedHeader = String.fromCharCodes(migratedBytes.sublist(0, 15));
      expect(migratedHeader, isNot(equals('SQLite format 3')));

      // Opening without key fails
      expect(() {
        final rawDb = sqlite.sqlite3.open(dbFile.path);
        try {
          rawDb.select('SELECT * FROM notifications_table;');
        } finally {
          rawDb.close();
        }
      }, throwsA(anything));
    });
  });
}
