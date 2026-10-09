import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/secure_key_storage.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureKeyStorage & PassphraseHolder Unit Tests', () {
    test('generate256BitPassphrase produces 64-char hex string with 256-bit entropy', () {
      final key1 = SecureKeyStorage.generate256BitPassphrase();
      final key2 = SecureKeyStorage.generate256BitPassphrase();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key1), isTrue);
    });

    test('PassphraseHolder stores passphrase and clears memory upon purge', () {
      final holder = PassphraseHolder('secret-passphrase-123');
      expect(holder.passphrase, equals('secret-passphrase-123'));

      holder.purge();
      expect(() => holder.passphrase, throwsStateError);
    });

    test('SecureKeyStorage retrieves or generates passphrase with FlutterSecureStorage', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final secureStorage = SecureKeyStorage(
        storage: const FlutterSecureStorage(),
      );

      final key1 = await secureStorage.getOrCreateDatabasePassphrase();
      expect(key1.length, equals(64));

      final key2 = await secureStorage.getOrCreateDatabasePassphrase();
      expect(key2, equals(key1));
    });
  });

  group('SQLCipher Migration Unit Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('migrateUnencryptedIfNeeded converts unencrypted SQLite database to SQLCipher format', () async {
      final dbFile = File('${tempDir.path}/test_unencrypted.db');
      final passphrase = SecureKeyStorage.generate256BitPassphrase();

      // 1. Create unencrypted SQLite database with sample table and data
      final initialDb = sqlite3.open(dbFile.path);
      initialDb.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, name TEXT);');
      initialDb.execute("INSERT INTO sample (id, name) VALUES (1, 'ScopeNotification');");
      initialDb.dispose();

      expect(dbFile.existsSync(), isTrue);

      // Verify file starts with 'SQLite format 3\x00'
      final headerBytes = await dbFile.openRead(0, 16).first;
      final headerStr = String.fromCharCodes(headerBytes);
      expect(headerStr.startsWith('SQLite format 3'), isTrue);

      // 2. Execute migration
      await migrateUnencryptedIfNeeded(dbFile, passphrase);

      expect(dbFile.existsSync(), isTrue);

      // 3. Verify opening with SQLCipher PRAGMA key successfully reads data
      final encryptedDb = sqlite3.open(dbFile.path);
      encryptedDb.execute("PRAGMA key = '$passphrase';");
      final results = encryptedDb.select('SELECT * FROM sample;');
      expect(results.length, equals(1));
      expect(results.first['name'], equals('ScopeNotification'));
      encryptedDb.dispose();
    });

    test('migrateUnencryptedIfNeeded skips migration when database is already encrypted', () async {
      final dbFile = File('${tempDir.path}/test_already_encrypted.db');
      final passphrase = SecureKeyStorage.generate256BitPassphrase();

      // Create encrypted database directly
      final createDb = sqlite3.open(dbFile.path);
      createDb.execute("PRAGMA key = '$passphrase';");
      createDb.execute('CREATE TABLE secure_data (id INTEGER PRIMARY KEY, secret TEXT);');
      createDb.execute("INSERT INTO secure_data (id, secret) VALUES (42, 'Confidential');");
      createDb.dispose();

      // Run migration on already encrypted database
      await migrateUnencryptedIfNeeded(dbFile, passphrase);

      // Verify database opens fine with passphrase and retains data
      final reopenDb = sqlite3.open(dbFile.path);
      reopenDb.execute("PRAGMA key = '$passphrase';");
      final results = reopenDb.select('SELECT * FROM secure_data;');
      expect(results.length, equals(1));
      expect(results.first['secret'], equals('Confidential'));
      reopenDb.dispose();
    });
  });
}
