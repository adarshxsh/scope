import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> storage = {};
  bool shouldThrow = false;

  @override
  Future<String?> read({
    required String key,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
    cOptions,
  }) async {
    if (shouldThrow) throw Exception('SecureStorage read failure');
    return storage[key];
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
    cOptions,
  }) async {
    if (shouldThrow) throw Exception('SecureStorage write failure');
    if (value == null) {
      storage.remove(key);
    } else {
      storage[key] = value;
    }
  }
}

void main() {
  group('SQLCipher Database Encryption & Key Management', () {
    late FakeSecureStorage fakeStorage;
    late Directory tempDir;

    setUp(() {
      fakeStorage = FakeSecureStorage();
      tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getOrCreateDatabaseKey generates and persists 256-bit hex passphrase', () async {
      final key1 = await getOrCreateDatabaseKey(secureStorage: fakeStorage);

      expect(key1.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key1), isTrue);
      expect(fakeStorage.storage['db_encryption_key'], equals(key1));

      final key2 = await getOrCreateDatabaseKey(secureStorage: fakeStorage);
      expect(key2, equals(key1));
    });

    test('getOrCreateDatabaseKey throws StateError on secure storage failure', () async {
      fakeStorage.shouldThrow = true;

      expect(
        () async => await getOrCreateDatabaseKey(secureStorage: fakeStorage),
        throwsA(isA<StateError>()),
      );
    });

    test('migrateUnencryptedDatabaseIfNeeded converts plaintext SQLite db to SQLCipher db', () async {
      final dbFile = File('${tempDir.path}/legacy_attention_os.db');

      // Create legacy unencrypted database with schema and data
      final rawDb = sqlite3.open(dbFile.path);
      rawDb.execute("CREATE TABLE notifications (id TEXT PRIMARY KEY, title TEXT);");
      rawDb.execute("CREATE INDEX idx_title ON notifications(title);");
      rawDb.execute("INSERT INTO notifications VALUES ('n1', 'Sensitive Message');");
      rawDb.dispose();

      // Confirm unencrypted SQLite header
      final initialBytes = dbFile.readAsBytesSync();
      expect(String.fromCharCodes(initialBytes.sublist(0, 15)), equals('SQLite format 3'));

      const key = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
      await migrateUnencryptedDatabaseIfNeeded(dbFile, key);

      // Verify database file exists and can be queried with PRAGMA key
      final migratedDb = sqlite3.open(dbFile.path);
      migratedDb.execute("PRAGMA key = '$key';");
      final rows = migratedDb.select("SELECT * FROM notifications;");
      expect(rows.length, equals(1));
      expect(rows.first['title'], equals('Sensitive Message'));
      migratedDb.dispose();
    });

    test('AttentionDatabase.withStorage opens database and operates normally', () async {
      final dbFile = File('${tempDir.path}/attention_os.db');
      final db = AttentionDatabase.withStorage(
        secureStorage: fakeStorage,
        dbFile: dbFile,
      );

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'secure-1',
        packageName: 'com.signal',
        title: 'Secret Agent',
        content: 'Confidential Payload',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      final fetched = await db.notificationDao.getById('secure-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Secret Agent'));
      expect(fetched.content, equals('Confidential Payload'));

      await db.close();

      // Confirm secure storage contains key
      expect(fakeStorage.storage['db_encryption_key'], isNotNull);
    });

    test('AttentionDatabase.inMemory() works without requiring platform secure storage', () async {
      final inMemoryDb = AttentionDatabase.inMemory();

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'mem-1',
        packageName: 'com.test',
        title: 'Memory Test',
        content: 'In-Memory Content',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await inMemoryDb.notificationDao.insertNotification(entry);
      final fetched = await inMemoryDb.notificationDao.getById('mem-1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals('In-Memory Content'));

      await inMemoryDb.close();
    });
  });
}
