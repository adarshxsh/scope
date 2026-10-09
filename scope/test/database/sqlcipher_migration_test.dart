import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';
import 'package:scope/database/secure_key_service.dart';
import 'package:scope/database/database_migrator.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SQLCipher Secure Key Service Tests', () {
    test('generateRandom256BitKey produces a 64-character hex string (256 bits)', () {
      final key = SecureKeyService.generateRandom256BitKey();
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('SecureKeyService getOrCreateDatabaseKey caches key and generates if missing', () async {
      final service = SecureKeyService();
      final key1 = await service.getOrCreateDatabaseKey();
      expect(key1.length, equals(64));

      final key2 = await service.getOrCreateDatabaseKey();
      expect(key2, equals(key1));
    });
  });

  group('SQLCipher Database Migration and Encryption Tests', () {
    test('Unencrypted database file is readable without key, but unreadable without key after migration', () async {
      final dbFile = File('${tempDir.path}/attention_os.db');
      final key = SecureKeyService.generateRandom256BitKey();

      // 1. Create an unencrypted SQLite database and populate sample data
      final unencryptedDb = sqlite3.open(dbFile.path);
      unencryptedDb.execute('''
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
      unencryptedDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at)
        VALUES ('unencrypted_1', 'com.example.bank', 'Bank Alert', 'Your account was credited \$500', 1700000000000, 'ACTIVE', 0, 0, 0, 1700000000);
      ''');
      unencryptedDb.execute('PRAGMA user_version = 1;');
      unencryptedDb.dispose();

      // Verify that unencrypted DB can be queried without key
      final checkUnencrypted = sqlite3.open(dbFile.path);
      final initialResult = checkUnencrypted.select('SELECT title, content FROM notifications_table;');
      expect(initialResult.length, equals(1));
      expect(initialResult.first['title'], equals('Bank Alert'));
      checkUnencrypted.dispose();

      // 2. Perform in-place migration to SQLCipher
      await DatabaseMigrator.migrateUnencryptedDatabaseIfNeeded(dbFile, key);

      // 3. Verify that attempting to open without key fails with 'file is not a database'
      final checkEncryptedWithoutKey = sqlite3.open(dbFile.path);
      expect(
        () => checkEncryptedWithoutKey.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>().having(
          (e) => e.message,
          'message',
          contains('file is not a database'),
        )),
      );
      checkEncryptedWithoutKey.dispose();

      // 4. Verify system process `sqlite3` CLI without key also fails
      final processResult = Process.runSync('sqlite3', [dbFile.path, 'SELECT * FROM notifications_table;']);
      expect(processResult.exitCode, isNot(equals(0)));
      expect(processResult.stderr.toString() + processResult.stdout.toString(), contains('file is not a database'));

      // 5. Verify opening with key succeeds and preserves stored notifications
      final escapedKey = key.replaceAll("'", "''");
      final nativeDb = NativeDatabase(
        dbFile,
        setup: (rawDb) => rawDb.execute("PRAGMA key = '$escapedKey';"),
      );
      final db = AttentionDatabase(nativeDb);

      final fetched = await db.notificationDao.getById('unencrypted_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Bank Alert'));
      expect(fetched.content, equals('Your account was credited \$500'));

      await db.close();
    });

    test('DriftNotificationStorage works seamlessly with encrypted AttentionDatabase', () async {
      final dbFile = File('${tempDir.path}/encrypted_attention.db');
      final keyService = SecureKeyService();
      final key = await keyService.getOrCreateDatabaseKey();
      final escapedKey = key.replaceAll("'", "''");

      final nativeDb = NativeDatabase(
        dbFile,
        setup: (rawDb) => rawDb.execute("PRAGMA key = '$escapedKey';"),
      );
      final db = AttentionDatabase(nativeDb, keyService);
      final storage = DriftNotificationStorage(db);

      final now = DateTime.now();
      final notification = AppNotification(
        id: 'secure_notif_100',
        packageName: 'com.whatsapp',
        title: 'Confidential Message',
        content: 'Secret OTP is 123456',
        timestamp: now.millisecondsSinceEpoch,
      );

      await storage.save(notification);

      final fetched = await storage.getById('secure_notif_100');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Confidential Message'));
      expect(fetched.content, equals('Secret OTP is 123456'));

      await db.close();

      // Ensure file on disk is encrypted
      final processResult = Process.runSync('sqlite3', [dbFile.path, 'SELECT * FROM notifications_table;']);
      expect(processResult.stderr.toString() + processResult.stdout.toString(), contains('file is not a database'));
    });
  });
}
