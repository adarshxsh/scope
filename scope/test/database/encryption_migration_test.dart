import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SQLCipher Database Encryption & Auto-Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_');
      SecureKeyStorage.setMockKey(null);
    });

    tearDown(() {
      SecureKeyStorage.setMockKey(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Isolated in-memory mode executes without hardware keychain', () async {
      final db = AttentionDatabase.inMemory();

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'mem-1',
        packageName: 'com.whatsapp',
        title: 'Secret Message',
        content: 'Top Secret OTP 123456',
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
      expect(fetched!.title, equals('Secret Message'));
      expect(fetched.content, equals('Top Secret OTP 123456'));

      await db.close();
    });

    test('Retrieves key from SecureKeyStorage and writes encrypted data to disk', () async {
      const testKey = '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';
      SecureKeyStorage.setMockKey(testKey);

      final dbFile = File('${tempDir.path}/attention_os.db');
      final db = AttentionDatabase.withKey(testKey, customFile: dbFile);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'enc-1',
        packageName: 'com.bank.app',
        title: 'Bank Alert',
        content: 'Your account was credited with \$500',
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
      expect(fetched!.title, equals('Bank Alert'));

      await db.close();

      expect(dbFile.existsSync(), isTrue);
    });

    test('Restricts access when encryption key is empty or invalid', () async {
      SecureKeyStorage.setMockKey('');

      expect(() async {
        await SecureKeyStorage.getDatabaseKey();
      }, throwsStateError);

      final dbFile = File('${tempDir.path}/attention_os.db');
      expect(() {
        AttentionDatabase.withKey('', customFile: dbFile);
      }, throwsStateError);
    });

    test('Automatically migrates existing plain text database to encrypted database', () async {
      final dbFile = File('${tempDir.path}/attention_os.db');
      const testKey = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

      // 1. Create an unencrypted SQLite database with existing user history
      final rawPlainDb = sqlite3.open(dbFile.path);
      rawPlainDb.execute('''
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
          state TEXT NOT NULL,
          snoozed_until INTEGER,
          last_updated INTEGER,
          policy_score REAL,
          final_score REAL,
          reviewed INTEGER NOT NULL DEFAULT 0,
          dismissed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''');
      rawPlainDb.execute('''
        CREATE TABLE review_queue_table (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          notification_id TEXT NOT NULL,
          priority TEXT NOT NULL,
          enqueue_time INTEGER NOT NULL,
          expiry_time INTEGER,
          status TEXT NOT NULL
        );
      ''');

      final plainNow = DateTime.now().millisecondsSinceEpoch;
      rawPlainDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at)
        VALUES ('mig-1', 'com.signal.app', 'Private Msg', 'Hello World Unencrypted', $plainNow, 'ACTIVE', 0, 0, 0, $plainNow);
      ''');
      rawPlainDb.execute('''
        INSERT INTO review_queue_table (notification_id, priority, enqueue_time, status)
        VALUES ('mig-1', 'high', $plainNow, 'ACTIVE');
      ''');
      rawPlainDb.dispose();

      // Verify database file exists and is unencrypted initially
      final checkUnenc = sqlite3.open(dbFile.path);
      final initialCount = checkUnenc.select("SELECT count(*) FROM notifications_table;");
      expect(initialCount.first['count(*)'], equals(1));
      checkUnenc.dispose();

      // 2. Launch AttentionDatabase with encryption key -> triggers automatic migration
      SecureKeyStorage.setMockKey(testKey);
      final dbEnc = AttentionDatabase.withKey(testKey, customFile: dbFile);

      // Verify migrated data through Drift ORM
      final fetchedNotif = await dbEnc.notificationDao.getById('mig-1');
      expect(fetchedNotif, isNotNull);
      expect(fetchedNotif!.title, equals('Private Msg'));
      expect(fetchedNotif.content, equals('Hello World Unencrypted'));

      final queueItems = await dbEnc.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      expect(queueItems.first.notificationId, equals('mig-1'));
      expect(queueItems.first.priority, equals('high'));

      await dbEnc.close();
    });
  });
}
