import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SQLCipher Database Encryption & Migration Integration Tests', () {
    test('creates 100% encrypted SQLCipher database at rest unreadable by sqlite3 CLI', () async {
      final dbFile = File('${tempDir.path}/attention_os.db');
      final keyStorage = InMemoryKeyStorage();
      final keyManager = DatabaseKeyManager(storage: keyStorage);

      final key = await keyManager.getOrCreateKey();
      expect(key, isNotNull);
      expect(key.length, equals(64));

      // 1. Initialize encrypted database file using SQLCipher
      final initRes = Process.runSync('sqlcipher', [
        dbFile.path,
        '''
        PRAGMA key = '$key';
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
        INSERT INTO notifications_table VALUES (
          'enc-1', 'com.signal.app', 'Secret Message', 'Confidential Payload', 1700000000, 'ACTIVE', 0, 0, 0, 1700000000
        );
        ''',
      ]);

      expect(initRes.exitCode, equals(0));
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));

      // 2. Check header magic bytes - must NOT be cleartext "SQLite format 3"
      final bytes = dbFile.readAsBytesSync().sublist(0, 15);
      final headerStr = String.fromCharCodes(bytes);
      expect(headerStr.startsWith('SQLite format 3'), isFalse);

      // 3. Standard sqlite3 CLI must fail to read or parse the database file without the valid encryption key
      final unencQuery = Process.runSync('sqlite3', [dbFile.path, 'SELECT * FROM notifications_table;']);
      expect(unencQuery.exitCode, isNot(equals(0)));
      expect(unencQuery.stderr, contains('file is not a database'));

      // 4. SQLCipher CLI with valid key reads data successfully
      final sqlcipherQuery = Process.runSync('sqlcipher', [
        dbFile.path,
        "PRAGMA key = '$key'; SELECT title, content FROM notifications_table WHERE id = 'enc-1';",
      ]);
      expect(sqlcipherQuery.exitCode, equals(0));
      expect(sqlcipherQuery.stdout, contains('Secret Message'));
      expect(sqlcipherQuery.stdout, contains('Confidential Payload'));

      // 5. SQLCipher CLI with WRONG key fails
      final wrongKeyQuery = Process.runSync('sqlcipher', [
        dbFile.path,
        "PRAGMA key = 'wrong_key_1234567890123456789012345678901234567890'; SELECT * FROM notifications_table;",
      ]);
      expect(wrongKeyQuery.exitCode, isNot(equals(0)));
      expect(wrongKeyQuery.stderr, contains('file is not a database'));
    });

    test('migrates existing unencrypted SQLite database to SQLCipher on app startup', () async {
      final dbFile = File('${tempDir.path}/unencrypted_attention.db');

      // 1. Create an unencrypted SQLite database with cleartext notification entries
      final unencDb = sqlite3.open(dbFile.path);
      unencDb.execute('''
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

      final now = DateTime.now().millisecondsSinceEpoch;
      unencDb.execute('''
        INSERT INTO notifications_table VALUES (
          'mig-1', 'com.whatsapp', 'Legacy Alert', 'Cleartext Body Payload', $now, 'ACTIVE', 0, 0, 0, $now
        );
      ''');
      unencDb.close();

      // Confirm file is cleartext SQLite before migration
      final headerBefore = String.fromCharCodes(dbFile.readAsBytesSync().sublist(0, 15));
      expect(headerBefore.startsWith('SQLite format 3'), isTrue);

      // Verify sqlite3 CLI can read unencrypted database before migration
      final preMigQuery = Process.runSync('sqlite3', [dbFile.path, 'SELECT title, content FROM notifications_table;']);
      expect(preMigQuery.exitCode, equals(0));
      expect(preMigQuery.stdout, contains('Legacy Alert'));

      // 2. Perform migration using DatabaseKeyManager & migrateUnencryptedDatabase
      final keyStorage = InMemoryKeyStorage();
      final keyManager = DatabaseKeyManager(storage: keyStorage);
      final key = await keyManager.getOrCreateKey();

      await migrateUnencryptedDatabase(dbFile, key);

      // 3. Confirm file is now encrypted with SQLCipher
      final headerAfter = String.fromCharCodes(dbFile.readAsBytesSync().sublist(0, 15));
      expect(headerAfter.startsWith('SQLite format 3'), isFalse);

      // Standard sqlite3 CLI must now fail without key
      final unencQueryAfter = Process.runSync('sqlite3', [dbFile.path, 'SELECT * FROM notifications_table;']);
      expect(unencQueryAfter.exitCode, isNot(equals(0)));
      expect(unencQueryAfter.stderr, contains('file is not a database'));

      // SQLCipher CLI with key must succeed and retrieve all pre-existing notification records
      final encQueryAfter = Process.runSync('sqlcipher', [
        dbFile.path,
        "PRAGMA key = '$key'; SELECT title, content FROM notifications_table WHERE id = 'mig-1';",
      ]);
      expect(encQueryAfter.exitCode, equals(0));
      expect(encQueryAfter.stdout, contains('Legacy Alert'));
      expect(encQueryAfter.stdout, contains('Cleartext Body Payload'));
    });
  });
}
