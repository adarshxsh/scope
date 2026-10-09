import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_storage_helper.dart';

class FailingSecureStorage extends FlutterSecureStorage {
  const FailingSecureStorage() : super();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('KeyStore hardware unavailable');
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('KeyStore write error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseKeyProvider Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('Generates 256-bit (64 hex char) key and persists to secure storage', () async {
      final keyProvider = DatabaseKeyProvider();
      final key1 = await keyProvider.getPassphrase();

      expect(key1, isNotEmpty);
      expect(key1.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key1), isTrue);

      // Subsequent call returns same key
      final key2 = await keyProvider.getPassphrase();
      expect(key2, equals(key1));
    });

    test('Fails gracefully when secure storage is unavailable', () async {
      final failingProvider = DatabaseKeyProvider(storage: const FailingSecureStorage());
      expect(
        () async => await failingProvider.getPassphrase(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Failed to access secure key storage'),
        )),
      );
    });
  });

  group('Unencrypted Database Migration & Detection Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_encrypt_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('isUnencryptedDatabase detects standard SQLite header', () {
      final unencryptedFile = File('${tempDir.path}/plain.db');
      final db = sqlite3.open(unencryptedFile.path);
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT);');
      db.execute("INSERT INTO test VALUES (1, 'sensitive_data');");
      db.close();

      expect(isUnencryptedDatabase(unencryptedFile), isTrue);

      final nonExistentFile = File('${tempDir.path}/nonexistent.db');
      expect(isUnencryptedDatabase(nonExistentFile), isFalse);

      final emptyFile = File('${tempDir.path}/empty.db')..createSync();
      expect(isUnencryptedDatabase(emptyFile), isFalse);
    });

    test('migrateUnencryptedToEncrypted encrypts existing unencrypted database file and hides plaintext', () {
      final dbFile = File('${tempDir.path}/legacy.db');
      final rawDb = sqlite3.open(dbFile.path);
      rawDb.execute('CREATE TABLE notifications (id TEXT PRIMARY KEY, title TEXT, content TEXT);');
      rawDb.execute("INSERT INTO notifications VALUES ('n1', 'Secret 2FA Code', 'Your OTP is 882910');");
      rawDb.close();

      expect(isUnencryptedDatabase(dbFile), isTrue);

      // Raw inspection before encryption contains plaintext "Secret 2FA Code"
      final rawBefore = dbFile.readAsStringSync(encoding: latin1);
      expect(rawBefore.contains('Secret 2FA Code'), isTrue);

      const passphrase = 'test_secret_passphrase_1234567890_256bit_key_hex_hash';
      migrateUnencryptedToEncrypted(dbFile, passphrase);

      // Verify file header is no longer unencrypted SQLite format 3
      expect(isUnencryptedDatabase(dbFile), isFalse);

      // Raw inspection after encryption contains zero plaintext notification titles or content
      final rawAfter = dbFile.readAsStringSync(encoding: latin1);
      expect(rawAfter.contains('Secret 2FA Code'), isFalse);
      expect(rawAfter.contains('Your OTP is 882910'), isFalse);
    });

    test('AttentionDatabase inMemory with passphrase operates seamlessly', () async {
      final db = AttentionDatabase.inMemory(passphrase: 'test_passphrase_123');
      final now = DateTime.now();
      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'n_encrypted_1',
        packageName: 'com.whatsapp',
        title: 'Encrypted Message',
        content: 'Hello via SQLCipher',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      final fetched = await db.notificationDao.getById('n_encrypted_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Encrypted Message'));
      expect(fetched.content, equals('Hello via SQLCipher'));
      await db.close();
    });
  });
}
