import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/database_key_service.dart';
import 'package:scope/database/database_migrator.dart';

class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({
    required String key,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
    macOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
    macOptions,
  }) async {
    if (value != null) {
      _storage[key] = value;
    } else {
      _storage.remove(key);
    }
  }
}

void main() {
  group('DatabaseKeyService Tests', () {
    test('generates cryptographically secure 256-bit hex key (64 hex characters)', () {
      final key = DatabaseKeyService.generateSecureKey();
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('persists generated key in secure storage and retrieves existing key', () async {
      final mockStorage = MockSecureStorage();
      final service = DatabaseKeyService(storage: mockStorage);

      final key1 = await service.getOrCreateKey();
      expect(key1.length, equals(64));

      final key2 = await service.getOrCreateKey();
      expect(key2, equals(key1));
    });
  });

  group('DatabaseMigrator Tests', () {
    late Directory tempDir;
    late String dbPath;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('db_encryption_test_');
      dbPath = '${tempDir.path}/attention_os.db';
      dbFile = File(dbPath);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('correctly identifies unencrypted SQLite database file', () {
      expect(DatabaseMigrator.isUnencryptedDatabase(dbFile), isFalse);

      final rawDb = sqlite3.open(dbPath);
      rawDb.execute('CREATE TABLE sample (id INT, value TEXT);');
      rawDb.execute("INSERT INTO sample VALUES (1, 'Sensitive Notification Data');");
      rawDb.close();

      expect(DatabaseMigrator.isUnencryptedDatabase(dbFile), isTrue);
    });

    test('migration runs without throwing on unencrypted database', () async {
      const sensitiveText = 'Secret Government Notification Content';
      final encryptionKey = DatabaseKeyService.generateSecureKey();

      // 1. Create legacy unencrypted database with plaintext data
      final unencryptedDb = sqlite3.open(dbPath);
      unencryptedDb.execute('CREATE TABLE notifications (id TEXT PRIMARY KEY, content TEXT);');
      unencryptedDb.execute("INSERT INTO notifications VALUES ('n100', '$sensitiveText');");
      unencryptedDb.close();

      // Verify file contains plaintext before migration
      final rawBytes = dbFile.readAsBytesSync();
      final rawContent = String.fromCharCodes(rawBytes);
      expect(rawContent.contains(sensitiveText), isTrue);

      // 2. Perform migration call
      await DatabaseMigrator.migrateIfUnencrypted(dbFile, encryptionKey);
    });
  });
}
