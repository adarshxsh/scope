import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_manager.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseKeyManager Tests', () {
    test('getOrCreateKey generates 256-bit (64 hex character) key', () async {
      final keyManager = DatabaseKeyManager();
      final key = await keyManager.getOrCreateKey();

      expect(key, isNotEmpty);
      expect(key.length, equals(64));
      // Hex string matching
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('getOrCreateKey returns cached key on subsequent calls', () async {
      final keyManager = DatabaseKeyManager();
      final key1 = await keyManager.getOrCreateKey();
      final key2 = await keyManager.getOrCreateKey();

      expect(key1, equals(key2));
    });

    test('setKeyForTesting overrides active key', () async {
      final keyManager = DatabaseKeyManager();
      const testKey = '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';
      keyManager.setKeyForTesting(testKey);

      final key = await keyManager.getOrCreateKey();
      expect(key, equals(testKey));
    });
  });

  group('AttentionDatabase Encryption Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('attention_os_enc_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('AttentionDatabase with key initializes and performs read/write operations', () async {
      final dbFile = File('${tempDir.path}/encrypted_attention_os.db');
      const key = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

      final db = AttentionDatabase.withFile(dbFile, key);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'enc-1',
        packageName: 'com.signal',
        title: 'Encrypted Message',
        content: 'Top Secret Payload',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('enc-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Encrypted Message'));
      expect(fetched.content, equals('Top Secret Payload'));

      await db.close();
    });

    test('Opening encrypted database with incorrect key throws SqliteException on query', () async {
      final dbFile = File('${tempDir.path}/corrupt_encrypted.db');

      // Create a non-sqlite / encrypted page file
      final randomBytes = Uint8List(4096);
      final rng = Random(123);
      for (var i = 0; i < randomBytes.length; i++) {
        randomBytes[i] = rng.nextInt(256);
      }
      dbFile.writeAsBytesSync(randomBytes);

      final db = sqlite3.open(dbFile.path);
      db.execute("PRAGMA key = \"x'0000000000000000000000000000000000000000000000000000000000000000'\";");

      expect(
        () => db.select('SELECT count(*) FROM sqlite_master;'),
        throwsA(isA<SqliteException>()),
      );

      db.close();
    });

    test('Automatic migration converts unencrypted SQLite file to encrypted SQLCipher format without data loss', () async {
      final unencryptedFile = File('${tempDir.path}/attention_os.db');
      const key = '9999888877776666555544443333222211110000aaaabbbbccccddddeeeeffff';

      // 1. Pre-populate an unencrypted database file using raw sqlite3
      final rawDb = sqlite3.open(unencryptedFile.path);
      rawDb.execute('''
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

      final now = DateTime.now().millisecondsSinceEpoch;
      rawDb.execute('''
        INSERT INTO notifications_table VALUES (
          'unenc-1', 'com.whatsapp', 'Pre-existing Title', 'Pre-existing Body',
          $now, 'ACTIVE', 0, 0, 0, $now
        );
      ''');
      rawDb.close();

      // Verify unencrypted file has "SQLite format 3" magic header
      final initialBytes = unencryptedFile.readAsBytesSync();
      expect(utf8.decode(initialBytes.sublist(0, 15)), equals('SQLite format 3'));

      // 2. Open AttentionDatabase pointing to this file. Automatic migration should run.
      final db = AttentionDatabase.withFile(unencryptedFile, key);

      // Verify pre-existing data was preserved through migration
      final fetched = await db.notificationDao.getById('unenc-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Pre-existing Title'));
      expect(fetched.content, equals('Pre-existing Body'));

      // Insert new entry in migrated database
      final newEntry = NotificationEntry(
        id: 'post-mig-1',
        packageName: 'com.telegram',
        title: 'New Encrypted Title',
        content: 'New Encrypted Content',
        timestamp: now,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );
      await db.notificationDao.insertNotification(newEntry);

      final fetchedNew = await db.notificationDao.getById('post-mig-1');
      expect(fetchedNew, isNotNull);
      expect(fetchedNew!.title, equals('New Encrypted Title'));

      await db.close();
    });

    test('databaseProvider initializes database instance and disposes properly', () async {
      final container = ProviderContainer();
      final db = container.read(databaseProvider);

      expect(db, isA<AttentionDatabase>());

      final fetched = await db.notificationDao.getAll();
      expect(fetched, isEmpty);

      container.dispose();
    });
  });
}
