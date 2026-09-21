import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';
import 'package:scope/database/database_cipher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_dir_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SQLCipher Encryption & Secure Key Storage Tests', () {
    test('SecureKeyStorage generates valid 256-bit hex passphrase', () {
      final key1 = SecureKeyStorage.generate256BitPassphrase();
      final key2 = SecureKeyStorage.generate256BitPassphrase();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key1), isTrue);
    });

    test('PassphraseHolder zeroes out buffer upon purge', () {
      final secret = 'a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890';
      final holder = PassphraseHolder(secret);

      expect(holder.bytes.every((b) => b == 0), isFalse);
      holder.purge();
      expect(holder.bytes.every((b) => b == 0), isTrue);
    });

    test('Unencrypted SQLite database transparently migrates to encrypted file', () async {
      final testSubDir = await tempDir.createTemp('sub_test_');
      final dbFile = File(p.join(testSubDir.path, 'attention_os.db'));

      // 1. Create a plaintext SQLite database file with full schema
      final rawDb = sqlite3.open(dbFile.path);
      rawDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT PRIMARY KEY,
          package_name TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          is_ongoing INTEGER NOT NULL DEFAULT 0,
          reviewed INTEGER NOT NULL DEFAULT 0,
          dismissed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''');
      rawDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, is_ongoing, reviewed, dismissed, created_at)
        VALUES ('n1', 'com.whatsapp', 'Alice', 'Sensitive Message 1', 1000, 0, 0, 0, 1000),
               ('n2', 'com.bank', 'OTP', 'Your code is 123456', 2000, 0, 0, 0, 2000);
      ''');
      rawDb.dispose();

      // Verify file header starts with 'SQLite format 3'
      final headerBytesBefore = dbFile.openSync(mode: FileMode.read).readSync(16);
      expect(String.fromCharCodes(headerBytesBefore).startsWith('SQLite format 3'), isTrue);

      // 2. Perform migration using 256-bit passphrase
      final passphrase = SecureKeyStorage.generate256BitPassphrase();
      AttentionDatabase.migrateUnencryptedIfNeeded(dbFile, passphrase);

      // 3. Verify file header is no longer standard plaintext 'SQLite format 3'
      final headerBytesAfter = dbFile.openSync(mode: FileMode.read).readSync(16);
      expect(String.fromCharCodes(headerBytesAfter).startsWith('SQLite format 3'), isFalse);

      // 4. Verify accessing without key fails (binary blob / unreadable)
      expect(() {
        final unauthDb = sqlite3.open(dbFile.path);
        try {
          unauthDb.select('SELECT * FROM notifications_table;');
        } finally {
          unauthDb.dispose();
        }
      }, throwsA(isA<SqliteException>()));

      // 5. Decrypt and verify migrated data records remain 100% intact
      final encryptedBytes = dbFile.readAsBytesSync();
      final decryptedBytes = DatabaseCipher.decrypt(encryptedBytes, passphrase);
      final unlockedFile = File(p.join(testSubDir.path, 'unlocked.db'));
      unlockedFile.writeAsBytesSync(decryptedBytes);

      final unlockedDb = sqlite3.open(unlockedFile.path);
      final rows = unlockedDb.select('SELECT * FROM notifications_table;');
      expect(rows.length, equals(2));
      expect(rows.first['title'], equals('Alice'));
      expect(rows.last['content'], equals('Your code is 123456'));
      unlockedDb.dispose();
    });

    test('SecureKeyStorage handles getOrCreatePassphrase fallback gracefully', () async {
      final storage = SecureKeyStorage();
      final key = await storage.getOrCreatePassphrase();
      expect(key.length, equals(64));
    });
  });
}
