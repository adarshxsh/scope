import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_manager.dart';

void main() {
  group('Database Key Manager Tests', () {
    test('generateSecure256BitKey returns 64-character hex string (256 bits)', () {
      final key1 = DatabaseKeyManager.generateSecure256BitKey();
      final key2 = DatabaseKeyManager.generateSecure256BitKey();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key1), isTrue);
    });

    test('getOrCreateKey returns a valid key', () async {
      final keyManager = DatabaseKeyManager();
      final key = await keyManager.getOrCreateKey();
      expect(key, isNotNull);
      expect(key.length, equals(64));
    });
  });

  group('SQLCipher Encryption & Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('In-memory encrypted database CRUD operations work', () async {
      final db = AttentionDatabase.inMemory(key: 'test_key_in_memory');
      final now = DateTime.now();

      final entry = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Secret Message',
        content: 'Encrypted Content',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      final fetched = await db.notificationDao.getById('n1');

      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Secret Message'));
      expect(fetched.content, equals('Encrypted Content'));

      await db.close();
    });

    test('Database file on disk is encrypted with SQLCipher and unreadable by standard SQLite', () async {
      final dbFile = File('${tempDir.path}/attention_encrypted.db');
      final key = DatabaseKeyManager.generateSecure256BitKey();

      final db = AttentionDatabase.withKey(key, file: dbFile);
      final now = DateTime.now();

      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'enc_1',
        packageName: 'com.secret.app',
        title: 'Confidential',
        content: 'Top Secret Payload',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      await db.close();

      expect(dbFile.existsSync(), isTrue);

      // 1. Confirm header does not start with plaintext "SQLite format 3"
      final isPlaintext = DatabaseMigrator.isUnencryptedDatabase(dbFile);
      expect(isPlaintext, isFalse);

      // 2. Confirm standard unencrypted sqlite3 query fails on encrypted file
      final rawDb = sqlite3.open(dbFile.path);
      expect(
        () => rawDb.execute('SELECT count(*) FROM sqlite_master;'),
        throwsA(isA<SqliteException>()),
      );
      rawDb.close();

      // 3. Confirm reading with the correct key retrieves the data successfully
      final reopenedDb = AttentionDatabase.withKey(key, file: dbFile);
      final fetched = await reopenedDb.notificationDao.getById('enc_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Confidential'));
      expect(fetched.content, equals('Top Secret Payload'));

      await reopenedDb.close();
    });

    test('Migration logic converts existing plaintext database into encrypted database', () async {
      final dbFile = File('${tempDir.path}/legacy_attention.db');
      final key = DatabaseKeyManager.generateSecure256BitKey();

      // 1. Create a legacy plaintext SQLite database file
      final plaintextDb = sqlite3.open(dbFile.path);
      plaintextDb.execute('''
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

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      plaintextDb.execute('''
        INSERT INTO notifications_table (
          id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at
        ) VALUES (
          'legacy_1', 'com.example.mail', 'Legacy Email', 'Unencrypted Body Text', $nowMs, 'ACTIVE', 0, 0, 0, $nowMs
        );
      ''');
      plaintextDb.close();

      // Verify file is legacy unencrypted SQLite database
      expect(DatabaseMigrator.isUnencryptedDatabase(dbFile), isTrue);

      // 2. Execute migration to SQLCipher encrypted database
      await DatabaseMigrator.migrateToEncrypted(dbFile: dbFile, key: key);

      // 3. Confirm file is now encrypted and no longer recognized as unencrypted SQLite
      expect(DatabaseMigrator.isUnencryptedDatabase(dbFile), isFalse);

      // 4. Confirm unencrypted sqlite3 query fails
      final rawDb = sqlite3.open(dbFile.path);
      expect(
        () => rawDb.execute('SELECT count(*) FROM sqlite_master;'),
        throwsA(isA<SqliteException>()),
      );
      rawDb.close();

      // 5. Open converted database via AttentionDatabase with key and verify data intact
      final migratedDb = AttentionDatabase.withKey(key, file: dbFile);
      final fetched = await migratedDb.notificationDao.getById('legacy_1');

      expect(fetched, isNotNull);
      expect(fetched!.id, equals('legacy_1'));
      expect(fetched.packageName, equals('com.example.mail'));
      expect(fetched.title, equals('Legacy Email'));
      expect(fetched.content, equals('Unencrypted Body Text'));

      await migratedDb.close();
    });
  });
}
