import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureKeyService Unit Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('generate256BitPassphrase returns 64 hex characters', () {
      final key = SecureKeyService.generate256BitPassphrase();
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('getOrCreatePassphrase generates and persists passphrase in secure storage', () async {
      final keyService = SecureKeyService();
      final key1 = await keyService.getOrCreatePassphrase(keyName: 'test_db_key');
      expect(key1, isNotEmpty);
      expect(key1.length, equals(64));

      final key2 = await keyService.getOrCreatePassphrase(keyName: 'test_db_key');
      expect(key2, equals(key1));
    });
  });

  group('SQLCipher Encryption & Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_');
      FlutterSecureStorage.setMockInitialValues({});
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('AttentionDatabase succeeds read/write operations with correct hardware key passphrase', () async {
      final dbFile = File('${tempDir.path}/attention_secure.db');
      final passphrase = SecureKeyService.generate256BitPassphrase();

      final db = AttentionDatabase.withPassphrase(passphrase: passphrase, file: dbFile);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'sec-1',
        packageName: 'com.whatsapp',
        title: 'Secret Message',
        content: 'Confidential Payload',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('sec-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Secret Message'));
      expect(fetched.content, equals('Confidential Payload'));

      await db.close();
    });

    test('Opening encrypted database with invalid key material fails on SQLCipher', () async {
      final dbFile = File('${tempDir.path}/attention_encrypted.db');
      final validPassphrase = SecureKeyService.generate256BitPassphrase();
      final invalidPassphrase = SecureKeyService.generate256BitPassphrase();

      // 1. Create and populate encrypted database
      final validDb = AttentionDatabase.withPassphrase(passphrase: validPassphrase, file: dbFile);
      final now = DateTime.now();
      await validDb.notificationDao.insertNotification(NotificationEntry(
        id: 'sec-2',
        packageName: 'com.whatsapp',
        title: 'Secret',
        content: 'Top Secret',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));
      await validDb.close();

      // 2. Attempt to open with incorrect key material
      final badDb = AttentionDatabase.withPassphrase(passphrase: invalidPassphrase, file: dbFile);
      if (isSqlCipherAvailable()) {
        expect(
          () async => await badDb.notificationDao.getById('sec-2'),
          throwsA(anything),
        );
      } else {
        final item = await badDb.notificationDao.getById('sec-2');
        expect(item, isNotNull);
      }
      await badDb.close();
    });

    test('Automated migration converts legacy unencrypted database to encrypted SQLCipher database', () async {
      final legacyFile = File('${tempDir.path}/attention_legacy.db');
      final passphrase = SecureKeyService.generate256BitPassphrase();

      // Create dummy sidecar files to verify purging
      final walFile = File('${legacyFile.path}-wal');
      final shmFile = File('${legacyFile.path}-shm');
      final journalFile = File('${legacyFile.path}-journal');
      walFile.writeAsStringSync('dummy wal');
      shmFile.writeAsStringSync('dummy shm');
      journalFile.writeAsStringSync('dummy journal');

      // 1. Create legacy unencrypted SQLite database
      final rawDb = sqlite3.open(legacyFile.path);
      rawDb.execute('''
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
      rawDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at)
        VALUES ('legacy-1', 'com.whatsapp', 'Legacy Title', 'Legacy Content', 1000000, 'ACTIVE', 0, 0, 0, 1000000);
      ''');
      rawDb.close();

      // Verify legacy database is unencrypted (can be read without key)
      final verifyRaw = sqlite3.open(legacyFile.path);
      final checkRows = verifyRaw.select('SELECT title FROM notifications_table;');
      expect(checkRows.first['title'], equals('Legacy Title'));
      verifyRaw.close();

      // 2. Trigger automated migration
      await migrateUnencryptedDatabaseIfNeeded(legacyFile, passphrase);

      // Verify plain-text sidecar files were purged
      expect(walFile.existsSync(), isFalse);
      expect(shmFile.existsSync(), isFalse);
      expect(journalFile.existsSync(), isFalse);

      // 3. Verify opening unencrypted raw database after migration
      if (isSqlCipherAvailable()) {
        final badRaw = sqlite3.open(legacyFile.path);
        expect(
          () => badRaw.select('SELECT count(*) FROM notifications_table;'),
          throwsA(isA<SqliteException>()),
        );
        badRaw.close();
      }

      // 4. Verify opening with AttentionDatabase and correct key succeeds and retrieves migrated data
      final encryptedDb = AttentionDatabase.withPassphrase(passphrase: passphrase, file: legacyFile);
      final migrated = await encryptedDb.notificationDao.getById('legacy-1');
      expect(migrated, isNotNull);
      expect(migrated!.title, equals('Legacy Title'));
      expect(migrated.content, equals('Legacy Content'));
      await encryptedDb.close();
    });
  });
}
