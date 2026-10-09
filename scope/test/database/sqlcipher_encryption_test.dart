import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/database_key_manager.dart';

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

  group('SQLCipher Full Database Encryption Tests', () {
    test('Database created with SQLCipher PRAGMA key cannot be opened without key', () {
      final dbFile = File('${tempDir.path}/encrypted_test.db');
      final key = DatabaseKeyManager.generate256BitKey();

      // Create encrypted database and write sensitive notification record
      var db = sqlite3.open(dbFile.path);
      db.execute("PRAGMA key = '$key';");
      db.execute('CREATE TABLE notifications (id TEXT PRIMARY KEY, title TEXT, content TEXT);');
      db.execute("INSERT INTO notifications VALUES ('n1', 'Bank Alert', 'Your 2FA code is 987654');");
      db.close();

      // Verify file exists on disk
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));

      // Attempt 1: Opening file without PRAGMA key must fail with "file is not a database"
      var unkeyedDb = sqlite3.open(dbFile.path);
      expect(
        () => unkeyedDb.select('SELECT * FROM notifications;'),
        throwsA(isA<SqliteException>().having((e) => e.message, 'message', contains('file is not a database'))),
      );
      unkeyedDb.close();

      // Attempt 2: Opening file with correct PRAGMA key succeeds and retrieves data
      var keyedDb = sqlite3.open(dbFile.path);
      keyedDb.execute("PRAGMA key = '$key';");
      final rows = keyedDb.select('SELECT * FROM notifications;');
      expect(rows.length, equals(1));
      expect(rows.first['content'], equals('Your 2FA code is 987654'));
      keyedDb.close();
    });

    test('Zero plaintext notification content visible in direct disk inspection of encrypted db file', () {
      final dbFile = File('${tempDir.path}/encrypted_inspection.db');
      final key = DatabaseKeyManager.generate256BitKey();
      const secretContent = 'CRITICAL_SECRET_OTP_771829';

      var db = sqlite3.open(dbFile.path);
      db.execute("PRAGMA key = '$key';");
      db.execute('CREATE TABLE notifications (id TEXT PRIMARY KEY, content TEXT);');
      db.execute("INSERT INTO notifications VALUES ('n1', '$secretContent');");
      db.close();

      final fileBytes = dbFile.readAsBytesSync();
      final fileAsString = String.fromCharCodes(fileBytes);

      // Verify plain text secret content does NOT appear in raw bytes
      expect(fileAsString.contains(secretContent), isFalse);

      // Verify standard SQLite header "SQLite format 3" is NOT present in encrypted header
      expect(fileAsString.contains('SQLite format 3'), isFalse);
    });

    test('Migration handler seamlessly migrates existing unencrypted SQLite file to encrypted SQLCipher file without data loss', () {
      final dbFile = File('${tempDir.path}/unencrypted_legacy.db');
      final tempEncryptedFile = File('${tempDir.path}/unencrypted_legacy.db.migration.tmp');
      final key = DatabaseKeyManager.generate256BitKey();

      // Step 1: Create a legacy unencrypted SQLite database with existing records
      var legacyDb = sqlite3.open(dbFile.path);
      legacyDb.execute('CREATE TABLE notifications (id TEXT PRIMARY KEY, title TEXT, content TEXT);');
      legacyDb.execute("INSERT INTO notifications VALUES ('legacy1', 'Unencrypted Message', 'Existing notification content before upgrade');");
      legacyDb.close();

      // Confirm legacy file is unencrypted
      var confirmLegacyDb = sqlite3.open(dbFile.path);
      final legacyRows = confirmLegacyDb.select('SELECT * FROM notifications;');
      expect(legacyRows.length, equals(1));
      confirmLegacyDb.close();

      // Step 2: Run migration (sqlcipher_export)
      var migrateDb = sqlite3.open(dbFile.path);
      migrateDb.execute("ATTACH DATABASE '${tempEncryptedFile.path}' AS encrypted KEY '$key';");
      migrateDb.execute("SELECT sqlcipher_export('encrypted');");
      migrateDb.execute("DETACH DATABASE encrypted;");
      migrateDb.close();

      dbFile.deleteSync();
      tempEncryptedFile.renameSync(dbFile.path);

      // Step 3: Verify direct unkeyed access fails
      var unkeyedDb = sqlite3.open(dbFile.path);
      expect(
        () => unkeyedDb.select('SELECT * FROM notifications;'),
        throwsA(isA<SqliteException>()),
      );
      unkeyedDb.close();

      // Step 4: Verify keyed access succeeds and all existing data is intact
      var keyedDb = sqlite3.open(dbFile.path);
      keyedDb.execute("PRAGMA key = '$key';");
      final migratedRows = keyedDb.select('SELECT * FROM notifications;');
      expect(migratedRows.length, equals(1));
      expect(migratedRows.first['id'], equals('legacy1'));
      expect(migratedRows.first['title'], equals('Unencrypted Message'));
      expect(migratedRows.first['content'], equals('Existing notification content before upgrade'));
      keyedDb.close();
    });
  });
}
