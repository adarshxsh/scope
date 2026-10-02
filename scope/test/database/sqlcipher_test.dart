import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

class FailingKeyStorageBackend implements KeyStorageBackend {
  @override
  Future<String?> read(String key) async {
    throw Exception('Storage read failed');
  }

  @override
  Future<void> write(String key, String value) async {
    throw Exception('Storage write failed');
  }

  @override
  Future<void> delete(String key) async {
    throw Exception('Storage delete failed');
  }
}

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

  group('SecureKeyStorage Unit Tests', () {
    test('generate256BitKey produces a 64-character hex string (256 bits)', () {
      final keyManager = DatabaseKeyManager(
        storageBackend: InMemoryKeyStorageBackend(),
      );
      final key = keyManager.generate256BitKey();

      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
    });

    test('getOrCreatePassphrase generates and persists key in storage', () async {
      final storage = InMemoryKeyStorageBackend();
      final keyManager = DatabaseKeyManager(storageBackend: storage);

      final key1 = await keyManager.getOrCreatePassphrase();
      expect(key1.length, equals(64));

      final key2 = await keyManager.getOrCreatePassphrase();
      expect(key2, equals(key1));
    });

    test('getOrCreatePassphrase handles storage errors with DatabaseKeyException', () async {
      final keyManager = DatabaseKeyManager(
        storageBackend: FailingKeyStorageBackend(),
      );

      expect(
        () async => await keyManager.getOrCreatePassphrase(),
        throwsA(isA<DatabaseKeyException>()),
      );
    });
  });

  group('SQLCipher Encryption & File Direct Examination Tests', () {
    test('Database encrypts data at rest and raw file content is ciphertext', () async {
      final dbFile = File('${tempDir.path}/attention_os_encrypted.db');
      final keyManager = DatabaseKeyManager(storageBackend: InMemoryKeyStorageBackend());
      final passphraseKey = await keyManager.getOrCreatePassphrase();

      final db = AttentionDatabase.encrypted(
        passphraseKey: passphraseKey,
        customFile: dbFile,
      );

      const secretTitle = 'CLASSIFIED_CONFIDENTIAL_TITLE_999';
      const secretContent = 'SECRET_NOTIFICATION_PAYLOAD_BODY_888';

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'n_secret_1',
        packageName: 'com.secret.bank',
        title: secretTitle,
        content: secretContent,
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      // Verify DAO reads correctly through encrypted connection
      final fetched = await db.notificationDao.getById('n_secret_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals(secretTitle));
      expect(fetched.content, equals(secretContent));

      await db.close();

      // Direct file examination of attention_os_encrypted.db
      expect(dbFile.existsSync(), isTrue);
      final rawBytes = await dbFile.readAsBytes();

      // 1. Assert header is NOT standard SQLite header
      expect(await isUnencryptedDatabase(dbFile), isFalse);

      final headerStr = String.fromCharCodes(rawBytes.sublist(0, 16));
      expect(headerStr.contains('SQLite format 3'), isFalse);

      // 2. Assert raw content on disk does NOT contain cleartext notification strings
      final rawString = String.fromCharCodes(
        Uint8List.fromList(rawBytes.map((b) => (b >= 32 && b <= 126) ? b : 32).toList()),
      );
      expect(rawString.contains(secretTitle), isFalse);
      expect(rawString.contains(secretContent), isFalse);
    });

    test('Database connection fails when opened with an invalid passphrase key', () async {
      final dbFile = File('${tempDir.path}/attention_os_valid.db');
      final keyManager = DatabaseKeyManager(storageBackend: InMemoryKeyStorageBackend());
      final validKey = await keyManager.getOrCreatePassphrase();

      // Create database with valid key
      final dbValid = AttentionDatabase.encrypted(
        passphraseKey: validKey,
        customFile: dbFile,
      );

      await dbValid.notificationDao.insertNotification(NotificationEntry(
        id: 'n1',
        packageName: 'com.example.app',
        title: 'Title',
        content: 'Content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));

      await dbValid.close();

      // Attempt to open the same database file with an invalid key
      const invalidKey = '0000000000000000000000000000000000000000000000000000000000000000';
      final dbInvalid = AttentionDatabase.encrypted(
        passphraseKey: invalidKey,
        customFile: dbFile,
      );

      expect(
        () async => await dbInvalid.notificationDao.getById('n1'),
        throwsA(anything),
      );

      await dbInvalid.close();
    });

    test('Migration converts existing unencrypted database to SQLCipher ciphertext', () async {
      final dbFile = File('${tempDir.path}/unencrypted_legacy.db');

      // 1. Create legacy unencrypted database
      final rawDb = raw_sqlite.sqlite3.open(dbFile.path);
      rawDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT NOT NULL PRIMARY KEY,
          package_name TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          category TEXT,
          is_ongoing INTEGER NOT NULL DEFAULT 0,
          priority TEXT,
          priority_score REAL,
          classified_category TEXT,
          explanation TEXT,
          latency_ms INTEGER,
          rule_version TEXT,
          model_version TEXT,
          engine_version TEXT,
          extracted_features TEXT,
          state TEXT NOT NULL DEFAULT 'ACTIVE',
          snoozed_until INTEGER,
          last_updated INTEGER,
          reviewed INTEGER NOT NULL DEFAULT 0,
          dismissed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''');

      const legacyTitle = 'UNENCRYPTED_LEGACY_TITLE';
      rawDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, created_at)
        VALUES ('legacy_1', 'com.unencrypted.app', '$legacyTitle', 'Legacy Body', 100000, 'ACTIVE', 0, 0, 100000);
      ''');
      rawDb.dispose();

      // Verify file is currently unencrypted
      expect(await isUnencryptedDatabase(dbFile), isTrue);

      // 2. Perform migration using AttentionDatabase initializer
      final keyManager = DatabaseKeyManager(storageBackend: InMemoryKeyStorageBackend());
      final passphraseKey = await keyManager.getOrCreatePassphrase();

      final dbMigrated = AttentionDatabase.encrypted(
        passphraseKey: passphraseKey,
        customFile: dbFile,
      );

      // Read migrated record via DAO
      final fetched = await dbMigrated.notificationDao.getById('legacy_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals(legacyTitle));

      await dbMigrated.close();

      // 3. Confirm file on disk is now encrypted ciphertext
      expect(await isUnencryptedDatabase(dbFile), isFalse);
    });
  });
}
