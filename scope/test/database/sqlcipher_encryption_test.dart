import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';
import 'package:scope/database/database_migrator.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // On Linux test environments, bind sqlcipher dynamic library for page encryption support
  if (Platform.isLinux) {
    try {
      open.overrideFor(OperatingSystem.linux, () {
        return DynamicLibrary.open('/usr/lib/x86_64-linux-gnu/libsqlcipher.so');
      });
    } catch (_) {}
  }

  group('SQLCipher Database Encryption & Secure Key Storage Tests', () {
    late Directory tempDir;
    late Map<String, String> mockSecureStorageValues;
    late FlutterSecureStorage mockSecureStorage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
      mockSecureStorageValues = {};

      FlutterSecureStorage.setMockInitialValues(mockSecureStorageValues);
      mockSecureStorage = const FlutterSecureStorage();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('DatabaseKeyService generates and retrieves 256-bit passphrase from secure storage', () async {
      final keyService = DatabaseKeyService(mockSecureStorage);

      final key1 = await keyService.getOrGeneratePassphrase();
      expect(key1, isNotEmpty);
      expect(key1.length, equals(64)); // 32 bytes in hex = 64 characters

      // Subsequent call retrieves the same passphrase
      final key2 = await keyService.getOrGeneratePassphrase();
      expect(key2, equals(key1));

      // Clearing passphrase removes key
      await keyService.clearPassphrase();
      final key3 = await keyService.getOrGeneratePassphrase();
      expect(key3, isNot(equals(key1)));
      expect(key3.length, equals(64));
    });

    test('PassphraseHolder zeroes memory buffer upon purge', () {
      final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final holder = PassphraseHolder(rawBytes);

      expect(holder.bytes, isNotNull);
      expect(holder.bytes, equals([1, 2, 3, 4, 5, 6, 7, 8]));

      holder.purge();
      expect(holder.bytes, isNull);
    });

    test('SQLite database file on disk is fully encrypted using SQLCipher', () async {
      final dbPath = '${tempDir.path}/encrypted_test.db';
      final passphrase = DatabaseKeyService.generateSecurePassphrase();

      final db = AttentionDatabase.encrypted(passphrase: passphrase, dbPath: dbPath);

      // Insert test notification record
      final notification = NotificationEntry(
        id: 'enc-notif-001',
        packageName: 'com.example.secret',
        title: 'CONFIDENTIAL_TITLE_XYZ',
        content: 'CONFIDENTIAL_BODY_12345',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(notification);
      final all = await db.notificationDao.getAll();
      expect(all.length, equals(1));

      await db.close();

      // Inspect database file on disk
      final dbFile = File(dbPath);
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));

      final fileBytes = dbFile.readAsBytesSync();

      // 1. Header must NOT be standard SQLite format signature
      final standardHeader = DatabaseMigrator.sqliteHeader;
      final fileHeader = fileBytes.sublist(0, 16);
      expect(fileHeader, isNot(equals(standardHeader)));

      // 2. Direct byte search for confidential plaintext string yields zero occurrences
      final fileString = String.fromCharCodes(fileBytes);
      expect(fileString.contains('CONFIDENTIAL_TITLE_XYZ'), isFalse);
      expect(fileString.contains('CONFIDENTIAL_BODY_12345'), isFalse);

      // 3. Opening file without passphrase fails or throws exception
      expect(() {
        final rawDb = sqlite3.sqlite3.open(dbPath);
        rawDb.select("SELECT * FROM notifications_table;");
        rawDb.dispose();
      }, throwsException);
    });

    test('Database unlocks and executes DAOs successfully with correct passphrase', () async {
      final dbPath = '${tempDir.path}/encrypted_dao_test.db';
      final passphrase = DatabaseKeyService.generateSecurePassphrase();

      // Open database and insert data
      var db = AttentionDatabase.encrypted(passphrase: passphrase, dbPath: dbPath);
      final notification = NotificationEntry(
        id: 'dao-notif-001',
        packageName: 'com.example.app',
        title: 'Dao Notification Title',
        content: 'Dao Notification Body',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );
      await db.notificationDao.insertNotification(notification);
      await db.close();

      // Reopen database with correct passphrase and verify access
      db = AttentionDatabase.encrypted(passphrase: passphrase, dbPath: dbPath);

      final retrieved = await db.notificationDao.getById('dao-notif-001');
      expect(retrieved, isNotNull);
      expect(retrieved!.title, equals('Dao Notification Title'));

      // Verify cleanup transactions work on encrypted database
      await db.runSetBasedCleanup(DateTime.now().millisecondsSinceEpoch + 1000);
      final remaining = await db.notificationDao.getAll();
      expect(remaining, isEmpty);

      await db.close();
    });

    test('Legacy unencrypted database file is migrated to SQLCipher encrypted file', () async {
      final dbPath = '${tempDir.path}/legacy_unencrypted.db';
      final passphrase = DatabaseKeyService.generateSecurePassphrase();

      // Create a legacy unencrypted SQLite database
      final rawDb = sqlite3.sqlite3.open(dbPath);
      rawDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT NOT NULL PRIMARY KEY,
          package_name TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          category TEXT,
          is_summary INTEGER NOT NULL DEFAULT 0,
          raw_payload TEXT,
          extracted_features TEXT,
          smart_actions TEXT,
          review_state INTEGER NOT NULL DEFAULT 0,
          state INTEGER NOT NULL DEFAULT 0,
          reviewed INTEGER NOT NULL DEFAULT 0,
          dismissed INTEGER NOT NULL DEFAULT 0,
          is_ongoing INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER,
          explanation TEXT
        );
      ''');
      rawDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at)
        VALUES ('legacy-001', 'com.example.legacy', 'UNENCRYPTED_LEGACY_TITLE', 'UNENCRYPTED_LEGACY_BODY', 1000, 'ACTIVE', 0, 0, 0, 1000);
      ''');
      rawDb.dispose();

      // Confirm legacy file is unencrypted
      final legacyBytes = File(dbPath).readAsBytesSync();
      expect(legacyBytes.sublist(0, 16), equals(DatabaseMigrator.sqliteHeader));
      expect(String.fromCharCodes(legacyBytes).contains('UNENCRYPTED_LEGACY_TITLE'), isTrue);

      // Open database using AttentionDatabase.encrypted - triggers automatic migration
      final db = AttentionDatabase.encrypted(passphrase: passphrase, dbPath: dbPath);

      final all = await db.notificationDao.getAll();
      expect(all.length, equals(1));

      final item = await db.notificationDao.getById('legacy-001');
      expect(item, isNotNull);
      expect(item!.title, equals('UNENCRYPTED_LEGACY_TITLE'));

      await db.close();

      // Confirm file on disk is now encrypted
      final migratedBytes = File(dbPath).readAsBytesSync();
      expect(migratedBytes.sublist(0, 16), isNot(equals(DatabaseMigrator.sqliteHeader)));
      expect(String.fromCharCodes(migratedBytes).contains('UNENCRYPTED_LEGACY_TITLE'), isFalse);
    });
  });
}
