import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

void main() {
  group('SecureKeyStorage & Key Generation Tests', () {
    test('generate256BitKey creates 64-character hex string', () {
      final key1 = SecureKeyStorage.generate256BitKey();
      final key2 = SecureKeyStorage.generate256BitKey();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key1), isTrue);
    });

    test('PassphraseHolder stores and purges key material', () {
      final key = SecureKeyStorage.generate256BitKey();
      final holder = PassphraseHolder(key);

      expect(holder.passphrase, equals(key));
      holder.purge();
      expect(holder.passphrase, isNull);
    });
  });

  group('SQLCipher Migration & Header Detection Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('isUnencryptedSqliteFile detects unencrypted SQLite headers', () {
      final unencryptedFile = File('${tempDir.path}/plain.db');
      final db = sqlite3.sqlite3.open(unencryptedFile.path);
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);');
      db.execute("INSERT INTO test (name) VALUES ('sample');");
      db.close();

      expect(isUnencryptedSqliteFile(unencryptedFile), isTrue);

      final dummyFile = File('${tempDir.path}/random.db');
      dummyFile.writeAsBytesSync(List<int>.generate(32, (i) => i * 7 % 256));
      expect(isUnencryptedSqliteFile(dummyFile), isFalse);

      final nonExistentFile = File('${tempDir.path}/non_existent.db');
      expect(isUnencryptedSqliteFile(nonExistentFile), isFalse);
    });

    test('migrateUnencryptedIfNeeded handles unencrypted database migration', () {
      final dbFile = File('${tempDir.path}/attention_os.db');
      final key = SecureKeyStorage.generate256BitKey();

      // Create an unencrypted SQLite database with legacy data
      final rawDb = sqlite3.sqlite3.open(dbFile.path);
      rawDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT PRIMARY KEY,
          package_name TEXT,
          title TEXT,
          content TEXT,
          timestamp INTEGER
        );
      ''');
      rawDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp)
        VALUES ('n1', 'com.whatsapp', 'Alice', 'Hello legacy', 123456789);
      ''');
      rawDb.close();

      expect(isUnencryptedSqliteFile(dbFile), isTrue);

      // Perform inline migration sequence
      migrateUnencryptedIfNeeded(dbFile, key);

      // Verify file exists after migration
      expect(dbFile.existsSync(), isTrue);
    });
  });
}
