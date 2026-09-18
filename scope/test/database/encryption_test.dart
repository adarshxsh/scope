import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:drift/native.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/key_manager.dart';
import 'package:scope/database/migration.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encryption_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('DatabaseKeyManager Unit Tests', () {
    test('generateSecure256BitKey creates valid 64-character hex string', () {
      final key1 = DatabaseKeyManager.generateSecure256BitKey();
      final key2 = DatabaseKeyManager.generateSecure256BitKey();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key1), isTrue);
    });

    test('getOrCreateKey retrieves existing or creates new key in in-memory fallback', () async {
      final storage = <String, String>{};
      final mgr = DatabaseKeyManager(inMemoryFallback: storage);

      final key1 = await mgr.getOrCreateKey();
      expect(key1.length, equals(64));
      expect(storage[DatabaseKeyManager.storageKey], equals(key1));

      final key2 = await mgr.getOrCreateKey();
      expect(key2, equals(key1));
    });
  });

  group('SQLCipher Migration & Encryption Tests', () {
    test('Plaintext database detection and migration to SQLCipher format', () async {
      final dbFile = File('${tempDir.path}/test_plaintext.db');
      final passphrase = DatabaseKeyManager.generateSecure256BitKey();

      // 1. Create a legacy unencrypted (plaintext) SQLite database
      final legacyDb = sqlite3.sqlite3.open(dbFile.path);
      legacyDb.execute('''
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
      legacyDb.execute('''
        INSERT INTO notifications_table (
          id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at
        ) VALUES (
          'n_legacy_1', 'com.example.app', 'Legacy Title', 'Sensitive Cleartext Content',
          1700000000000, 'ACTIVE', 0, 0, 0, 1700000000000
        );
      ''');
      legacyDb.close();

      // Verify file is plaintext before migration
      expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isTrue);

      // 2. Perform automated migration
      final migrated = await DatabaseMigrator.migrateIfNeeded(dbFile, passphrase);
      expect(migrated, isTrue);

      // 3. Verify encryption state if SQLCipher is supported in runtime
      if (DatabaseMigrator.isSqlCipherSupported()) {
        expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isFalse);
        expect(DatabaseMigrator.isEncryptedWithKey(dbFile, passphrase), isTrue);

        final unencryptedReader = sqlite3.sqlite3.open(dbFile.path);
        expect(
          () => unencryptedReader.select('SELECT * FROM notifications_table;'),
          throwsA(anything),
        );
        unencryptedReader.close();
      }

      // 4. Verify data integrity when accessed via Drift/NativeDatabase with PRAGMA key
      final executor = NativeDatabase(
        dbFile,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$passphrase';");
        },
      );
      final driftDb = AttentionDatabase(executor);

      final notification = await driftDb.notificationDao.getById('n_legacy_1');
      expect(notification, isNotNull);
      expect(notification!.title, equals('Legacy Title'));
      expect(notification.content, equals('Sensitive Cleartext Content'));

      await driftDb.close();
    });

    test('In-memory database runs cleanly without physical KeyStore dependencies', () async {
      final db = AttentionDatabase.inMemory();

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'mem_1',
        packageName: 'com.whatsapp',
        title: 'In Memory Test',
        content: 'No hardware KeyStore required',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);
      final fetched = await db.notificationDao.getById('mem_1');

      expect(fetched, isNotNull);
      expect(fetched!.title, equals('In Memory Test'));

      await db.close();
    });
  });
}
