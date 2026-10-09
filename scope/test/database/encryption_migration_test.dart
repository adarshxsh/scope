import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

bool hasSqlCipherSupport() {
  try {
    final db = sqlite3.openInMemory();
    final res = db.select('PRAGMA cipher_version;');
    db.dispose();
    return res.isNotEmpty;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('scope_encryption_test_');
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SecureKeyStorage & PassphraseHolder Unit Tests', () {
    test('generate256BitKey generates 64-character hex string (256 bits)', () {
      final key1 = SecureKeyStorage.generate256BitKey();
      final key2 = SecureKeyStorage.generate256BitKey();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key1), isTrue);
    });

    test('getOrCreatePassphrase generates and persists 256-bit passphrase in secure storage', () async {
      const storage = FlutterSecureStorage();
      final secureKeyStorage = SecureKeyStorage(storage: storage);

      final initialPassphrase = await secureKeyStorage.getPassphrase();
      expect(initialPassphrase, isNull);

      final createdPassphrase = await secureKeyStorage.getOrCreatePassphrase();
      expect(createdPassphrase, isNotNull);
      expect(createdPassphrase.length, equals(64));

      final retrievedPassphrase = await secureKeyStorage.getPassphrase();
      expect(retrievedPassphrase, equals(createdPassphrase));

      await secureKeyStorage.clearPassphrase();
      expect(await secureKeyStorage.getPassphrase(), isNull);
    });

    test('PassphraseHolder stores bytes and purges memory buffer upon purge()', () {
      const testKey = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final holder = PassphraseHolder(testKey);

      expect(holder.isPurged, isFalse);
      expect(holder.passphrase, equals(testKey));

      holder.purge();

      expect(holder.isPurged, isTrue);
      expect(() => holder.passphrase, throwsStateError);
    });
  });

  group('SQLCipher Migration & Disk Encryption Tests', () {
    test('isUnencryptedSqlite correctly identifies unencrypted SQLite headers', () {
      final dbPath = '${tempDir.path}/plain.db';
      final dbFile = File(dbPath);

      expect(isUnencryptedSqlite(dbFile), isFalse);

      final rawDb = sqlite3.open(dbPath);
      rawDb.execute('CREATE TABLE dummy (id INT);');
      rawDb.dispose();

      expect(isUnencryptedSqlite(dbFile), isTrue);
    });

    test('migrateUnencryptedIfNeeded transforms unencrypted SQLite file without record loss', () async {
      final dbPath = '${tempDir.path}/legacy_attention_os.db';
      final dbFile = File(dbPath);
      final passphrase = SecureKeyStorage.generate256BitKey();

      // 1. Create legacy unencrypted SQLite database with sample notification records
      final rawDb = sqlite3.open(dbPath);
      rawDb.execute('''
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
      rawDb.execute('''
        INSERT INTO notifications_table (
          id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at
        ) VALUES (
          'migrated-1', 'com.whatsapp', 'Secret Title', 'Sensitive Message Body', 1700000000000, 'ACTIVE', 0, 0, 0, 1700000000000
        );
      ''');
      rawDb.dispose();

      expect(isUnencryptedSqlite(dbFile), isTrue);

      // 2. Perform transparent migration
      await migrateUnencryptedIfNeeded(dbFile, passphrase);

      final isSqlCipher = hasSqlCipherSupport();

      if (isSqlCipher) {
        // File is no longer plain SQLite format when SQLCipher is active
        expect(isUnencryptedSqlite(dbFile), isFalse);

        // Accessing without PRAGMA key fails
        final unauthedDb = sqlite3.open(dbPath);
        expect(
          () => unauthedDb.select('SELECT * FROM notifications_table;'),
          throwsA(isA<SqliteException>()),
        );
        unauthedDb.dispose();
      }

      // 3. Verify accessing with correct PRAGMA key retrieves historical data intact
      final authedDb = sqlite3.open(dbPath);
      authedDb.execute("PRAGMA key = '$passphrase';");
      final rows = authedDb.select('SELECT * FROM notifications_table;');
      expect(rows.length, equals(1));
      expect(rows.first['id'], equals('migrated-1'));
      expect(rows.first['title'], equals('Secret Title'));
      expect(rows.first['content'], equals('Sensitive Message Body'));
      authedDb.dispose();
    });

    test('AttentionDatabase operates transparently on NativeDatabase executor with PRAGMA key', () async {
      final dbPath = '${tempDir.path}/encrypted_attention_os.db';
      final dbFile = File(dbPath);
      final passphrase = SecureKeyStorage.generate256BitKey();

      final db = AttentionDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$passphrase';");
          },
        ),
      );

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'enc-n1',
        packageName: 'com.signal',
        title: 'Encrypted Title',
        content: 'Encrypted Payload Content',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('enc-n1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Encrypted Title'));
      expect(fetched.content, equals('Encrypted Payload Content'));

      await db.close();

      if (hasSqlCipherSupport()) {
        expect(isUnencryptedSqlite(dbFile), isFalse);
        final unauthedDb = sqlite3.open(dbFile.path);
        expect(
          () => unauthedDb.select('SELECT * FROM notifications_table;'),
          throwsA(isA<SqliteException>()),
        );
        unauthedDb.dispose();
      }
    });

    test('AttentionDatabase.inMemory() operates seamlessly in CI without physical keystore hardware', () async {
      final db = AttentionDatabase.inMemory();

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'mem-1',
        packageName: 'com.test',
        title: 'In Memory',
        content: 'Testing in CI',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      final fetched = await db.notificationDao.getById('mem-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('In Memory'));

      await db.close();
    });
  });
}
