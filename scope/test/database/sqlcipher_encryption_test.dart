import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_manager.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_env_');
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SQLCipher Database Encryption & Secure Key Storage Tests', () {
    test('DatabaseKeyManager generates and persists 256-bit passphrase', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final keyManager = DatabaseKeyManager();

      final passphrase1 = await keyManager.getOrCreatePassphrase();
      expect(passphrase1, isNotEmpty);
      expect(passphrase1.length, equals(64)); // 256-bit hex string

      // Verify second retrieval returns the same stored key
      final passphrase2 = await keyManager.getOrCreatePassphrase();
      expect(passphrase2, equals(passphrase1));
    });

    test('Encrypted database file operations remain transparent to DAOs', () async {
      final dbFile = File(p.join(tempDir.path, 'attention_os.db'));
      final keyManager = DatabaseKeyManager();
      final passphrase = await keyManager.getOrCreatePassphrase();

      // Open database with SQLCipher encryption
      final db = AttentionDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$passphrase';");
          },
        ),
      );

      final now = DateTime.now();
      final notification = NotificationEntry(
        id: 'enc-1',
        packageName: 'com.whatsapp',
        title: 'Encrypted Message',
        content: 'Sensitive OTP 992812',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(notification);
      final fetched = await db.notificationDao.getById('enc-1');

      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Encrypted Message'));
      expect(fetched.content, equals('Sensitive OTP 992812'));

      await db.close();
    });

    test('Direct inspection of encrypted db file without key fails', () async {
      final dbFile = File(p.join(tempDir.path, 'attention_os.db'));
      final keyManager = DatabaseKeyManager();
      final passphrase = await keyManager.getOrCreatePassphrase();

      final db = AttentionDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$passphrase';");
          },
        ),
      );

      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'enc-secret',
        packageName: 'com.bank.app',
        title: 'Transaction',
        content: 'Account debited',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));
      await db.close();

      // Try opening encrypted file with raw sqlite3 without providing PRAGMA key
      final rawDb = sqlite3.open(dbFile.path);
      expect(
        () => rawDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
        reason: 'Raw sqlite3 without PRAGMA key must fail to read encrypted database headers or tables',
      );
      rawDb.close();
    });

    test('Legacy unencrypted database is migrated in-place using sqlcipher_export', () async {
      final dbFile = File(p.join(tempDir.path, 'attention_os.db'));

      // 1. Create legacy unencrypted database using Drift
      final legacyDb = AttentionDatabase(NativeDatabase(dbFile));
      final now = DateTime.now();
      await legacyDb.notificationDao.insertNotification(NotificationEntry(
        id: 'legacy-1',
        packageName: 'com.legacy.app',
        title: 'Legacy Title',
        content: 'Unencrypted Body',
        timestamp: 1000000,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));
      await legacyDb.close();

      // Verify unencrypted legacy file can be read without key
      final checkRaw = sqlite3.open(dbFile.path);
      final checkRows = checkRaw.select('SELECT * FROM notifications_table;');
      expect(checkRows.length, equals(1));
      checkRaw.close();

      // 2. Perform in-place migration
      final keyManager = DatabaseKeyManager();
      final passphrase = await keyManager.getOrCreatePassphrase();
      await ensureEncrypted(dbFile, passphrase);

      // 3. Verify file is now encrypted (reading without key fails)
      final noKeyDb = sqlite3.open(dbFile.path);
      expect(
        () => noKeyDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      noKeyDb.close();

      // 4. Verify opening with Drift encrypted database retrieves migrated data
      final db = AttentionDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute("PRAGMA key = '$passphrase';");
          },
        ),
      );

      final migrated = await db.notificationDao.getById('legacy-1');
      expect(migrated, isNotNull);
      expect(migrated!.title, equals('Legacy Title'));
      expect(migrated.content, equals('Unencrypted Body'));

      await db.close();
    });

    test('Cold startup key retrieval and database handle creation benchmark (< 15ms)', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final keyManager = DatabaseKeyManager();

      final stopwatch = Stopwatch()..start();
      final passphrase = await keyManager.getOrCreatePassphrase();
      final dbFile = File(p.join(tempDir.path, 'benchmark.db'));

      final rawDb = sqlite3.open(dbFile.path);
      rawDb.execute("PRAGMA key = '$passphrase';");
      rawDb.execute('SELECT 1;');
      rawDb.close();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(15));
    });
  });
}
