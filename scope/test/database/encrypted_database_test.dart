import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/security/database_key_manager.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scope_db_test_');
    DatabaseKeyManager.resetInMemoryFallback();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SQLCipher Database Encryption & Security Tests', () {
    test('DatabaseKeyManager generates and retrieves a 256-bit passphrase', () async {
      final keyManager = DatabaseKeyManager();
      final key1 = await keyManager.getOrCreatePassphrase();

      expect(key1, isNotEmpty);
      expect(key1.length, equals(64)); // 32 bytes in hex = 64 characters
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key1), isTrue);

      final key2 = await keyManager.getOrCreatePassphrase();
      expect(key2, equals(key1));
    });

    test('Database file on disk is encrypted via SQLCipher AES-256', () async {
      final dbFile = File('${tempDir.path}/attention_os.db');
      final passphrase = DatabaseKeyManager.generateSecureKey();

      final db = AttentionDatabase.encryptedFile(dbFile, passphrase: passphrase);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'sec_1',
        packageName: 'com.bank.app',
        title: 'SENSITIVE_ALERT_CONFIDENTIAL',
        content: 'Transfer \$5000 USD completed successfully',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      await db.close();

      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));

      // Direct inspection: Plaintext sensitive content MUST NOT appear in raw bytes
      final rawBytes = await dbFile.readAsBytes();
      final rawText = String.fromCharCodes(rawBytes);

      expect(rawText.contains('SENSITIVE_ALERT_CONFIDENTIAL'), isFalse);
      expect(rawText.contains('Transfer \$5000 USD'), isFalse);

      // Direct raw sqlite3 inspection without passphrase MUST fail
      final unauthenticatedDb = sqlite3.open(dbFile.path);
      expect(
        () => unauthenticatedDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      unauthenticatedDb.close();

      // Opening with the valid passphrase MUST succeed and recover data
      final reopenedDb = AttentionDatabase.encryptedFile(dbFile, passphrase: passphrase);
      final fetched = await reopenedDb.notificationDao.getById('sec_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('SENSITIVE_ALERT_CONFIDENTIAL'));
      expect(fetched.content, equals('Transfer \$5000 USD completed successfully'));
      await reopenedDb.close();
    });

    test('Unencrypted legacy database file migrates to encrypted SQLCipher format', () async {
      final dbFile = File('${tempDir.path}/legacy_attention_os.db');

      // 1. Create unencrypted legacy database file
      final legacyRawDb = sqlite3.open(dbFile.path);
      legacyRawDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT NOT NULL PRIMARY KEY,
          package_name TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          state INTEGER NOT NULL,
          reviewed INTEGER NOT NULL,
          dismissed INTEGER NOT NULL,
          is_ongoing INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');
      legacyRawDb.execute('''
        INSERT INTO notifications_table (
          id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at
        ) VALUES (
          'unenc_1', 'com.legacy', 'UNENCRYPTED_LEGACY_TITLE', 'Plaintext secret payload', 123456789, 'ACTIVE', 0, 0, 0, 123456789
        );
      ''');
      legacyRawDb.close();

      // Verify unencrypted legacy file header starts with SQLite format 3
      final rawHeader = await dbFile.openRead(0, 16).first;
      final sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
      expect(rawHeader, equals(sqliteHeader));

      final passphrase = DatabaseKeyManager.generateSecureKey();

      // 2. Open via AttentionDatabase which triggers migrateUnencryptedDatabaseIfNeeded
      final migratedDb = AttentionDatabase.encryptedFile(dbFile, passphrase: passphrase);

      final fetched = await migratedDb.notificationDao.getById('unenc_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('UNENCRYPTED_LEGACY_TITLE'));
      expect(fetched.content, equals('Plaintext secret payload'));

      await migratedDb.close();

      // 3. Verify database file is now fully encrypted on disk
      final newHeader = await dbFile.openRead(0, 16).first;
      expect(newHeader, isNot(equals(sqliteHeader)));

      final rawBytesAfter = await dbFile.readAsBytes();
      final textAfter = String.fromCharCodes(rawBytesAfter);
      expect(textAfter.contains('UNENCRYPTED_LEGACY_TITLE'), isFalse);
      expect(textAfter.contains('Plaintext secret payload'), isFalse);

      final directRawDb = sqlite3.open(dbFile.path);
      expect(
        () => directRawDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      directRawDb.close();
    });
  });
}
