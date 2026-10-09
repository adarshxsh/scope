import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/key_storage_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('db_enc_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('KeyStorageService Unit Tests', () {
    test('generates a valid 256-bit hex key (64 hex characters)', () async {
      final keyService = KeyStorageService();
      final key = await keyService.getOrCreateEncryptionKey();
      expect(key, isNotNull);
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('retrieves same key on subsequent calls', () async {
      final keyService = KeyStorageService();
      final key1 = await keyService.getOrCreateEncryptionKey();
      final key2 = await keyService.getOrCreateEncryptionKey();
      expect(key1, equals(key2));
    });
  });

  group('SQLCipher Database Encryption & Disk Inspection Tests', () {
    test('initialization configures SQLCipher and creates an encrypted database file at rest', () async {
      final dbPath = '${tempDir.path}/encrypted_attention.db';
      final keyService = KeyStorageService();

      final db = AttentionDatabase.onDisk(
        keyStorageService: keyService,
        dbPath: dbPath,
      );

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'enc_n1',
        packageName: 'com.secret.bank',
        title: 'Top Secret Bank Notification Title',
        content: 'Confidential notification body with sensitive text 123456',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      await db.close();

      final file = File(dbPath);
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final fileString = String.fromCharCodes(bytes);

      // 1. Unencrypted header 'SQLite format 3' must NOT be present
      expect(fileString.contains('SQLite format 3'), isFalse);

      // 2. Sensitive notification contents must NOT be visible in plaintext
      expect(fileString.contains('Top Secret Bank Notification Title'), isFalse);
      expect(fileString.contains('Confidential notification body with sensitive text 123456'), isFalse);

      // 3. Opening plain sqlite3 without PRAGMA key fails to query
      final plainSqlite = sqlite3.open(dbPath);
      expect(() => plainSqlite.select('SELECT * FROM notifications;'), throwsA(anything));
      plainSqlite.close();

      // 4. Opening via AttentionDatabase decrypts and loads data correctly
      final dbReopened = AttentionDatabase.onDisk(
        keyStorageService: keyService,
        dbPath: dbPath,
      );

      final fetched = await dbReopened.notificationDao.getById('enc_n1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Top Secret Bank Notification Title'));
      expect(fetched.content, equals('Confidential notification body with sensitive text 123456'));
      await dbReopened.close();
    });
  });

  group('Automatic Migration from Unencrypted Database Tests', () {
    test('converts pre-existing unencrypted database instances to encrypted instances successfully', () async {
      final dbPath = '${tempDir.path}/legacy_unencrypted.db';

      // Step 1: Create a legacy unencrypted SQLite database with existing user records
      final legacyDb = sqlite3.open(dbPath);
      legacyDb.execute('''
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
      legacyDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at)
        VALUES ('leg_1', 'com.whatsapp', 'Legacy Alice', 'Legacy plaintext notification body content', 1700000000000, 'ACTIVE', 0, 0, 0, 1700000000);
      ''');
      legacyDb.close();

      // Verify legacy file is unencrypted
      final legacyBytes = File(dbPath).readAsBytesSync();
      final legacyString = String.fromCharCodes(legacyBytes);
      expect(legacyString.contains('SQLite format 3'), isTrue);
      expect(legacyString.contains('Legacy plaintext notification body content'), isTrue);

      // Step 2: Initialize AttentionDatabase on the unencrypted file (triggers automatic migration)
      final keyService = KeyStorageService();
      final migratedDb = AttentionDatabase.onDisk(
        keyStorageService: keyService,
        dbPath: dbPath,
      );

      // Verify legacy user notification data was migrated without loss
      final migratedEntry = await migratedDb.notificationDao.getById('leg_1');
      expect(migratedEntry, isNotNull);
      expect(migratedEntry!.title, equals('Legacy Alice'));
      expect(migratedEntry.content, equals('Legacy plaintext notification body content'));

      // Write a new entry to the migrated database
      final now = DateTime.now();
      await migratedDb.notificationDao.insertNotification(NotificationEntry(
        id: 'new_after_mig',
        packageName: 'com.slack',
        title: 'New Slack Msg',
        content: 'Post-migration message content',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      await migratedDb.close();

      // Step 3: Inspect raw file on disk after migration
      final encBytes = File(dbPath).readAsBytesSync();
      final encString = String.fromCharCodes(encBytes);

      expect(encString.contains('SQLite format 3'), isFalse);
      expect(encString.contains('Legacy plaintext notification body content'), isFalse);
      expect(encString.contains('Post-migration message content'), isFalse);

      // Step 4: Re-open and verify both old migrated and new records exist
      final reopenedDb = AttentionDatabase.onDisk(
        keyStorageService: keyService,
        dbPath: dbPath,
      );

      final allNotifications = await reopenedDb.notificationDao.getAll();
      expect(allNotifications.length, equals(2));
      expect(allNotifications.any((n) => n.id == 'leg_1'), isTrue);
      expect(allNotifications.any((n) => n.id == 'new_after_mig'), isTrue);

      await reopenedDb.close();
    });
  });
}
