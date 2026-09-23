import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite3;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/database_key_manager.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AttentionDatabase db;

  setUp(() {
    // Instantiate in-memory database for testing
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SQLCipher Transparent Database Encryption Tests', () {
    test('DatabaseKeyManager generates and retrieves a 256-bit hex key', () async {
      DatabaseKeyManager.resetState();
      final manager = DatabaseKeyManager();
      final key1 = await manager.getOrCreateKey();

      expect(key1, isNotEmpty);
      expect(key1.length, equals(64)); // 32 bytes = 64 hex characters (256-bit key)

      final key2 = await manager.getOrCreateKey();
      expect(key2, equals(key1));
    });

    test('NativeDatabase with SQLCipher PRAGMA key transparently encrypts data at rest', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_enc_test_');
      final dbFile = File('${tempDir.path}/test_encrypted.db');
      final key = DatabaseKeyManager.generate256BitKey();

      final executor = NativeDatabase(
        dbFile,
        setup: (database) {
          database.execute("PRAGMA key = '$key';");
        },
      );

      final encDb = AttentionDatabase(executor);

      const secretContent = 'Confidential message content 12345';
      final now = DateTime.now();
      await encDb.notificationDao.insertNotification(NotificationEntry(
        id: 'secret_1',
        packageName: 'com.secure.app',
        title: 'Private Alert',
        content: secretContent,
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      final retrieved = await encDb.notificationDao.getById('secret_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.content, equals(secretContent));

      await encDb.close();

      // Inspect raw database file on disk
      final bytes = await dbFile.readAsBytes();
      final rawContent = String.fromCharCodes(bytes);

      // Header must NOT match plaintext SQLite format header
      expect(bytes.take(16).toList(), isNot(equals('SQLite format 3\x00'.codeUnits)));
      // Raw notification text must NOT be visible anywhere in disk bytes
      expect(rawContent.contains(secretContent), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('Database migration converts pre-existing unencrypted file to encrypted SQLCipher format', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_mig_test_');
      final dbFile = File('${tempDir.path}/attention_os.db');
      final key = DatabaseKeyManager.generate256BitKey();

      // 1. Write an unencrypted SQLite database
      final unencDb = raw_sqlite3.sqlite3.open(dbFile.path);
      unencDb.execute('''
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
          reviewed INTEGER NOT NULL DEFAULT 0,
          dismissed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''');
      unencDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, is_ongoing, reviewed, dismissed, created_at)
        VALUES ('legacy_1', 'com.unencrypted', 'Legacy Title', 'Plaintext Legacy Notification Data', 100000, 'ACTIVE', 0, 0, 0, 100000);
      ''');
      unencDb.dispose();

      // Verify it was unencrypted initially
      var bytes = await dbFile.readAsBytes();
      expect(String.fromCharCodes(bytes.take(16)), equals('SQLite format 3\x00'));

      // 2. Open via NativeDatabase with PRAGMA key after migrating
      final tempFile = File('${dbFile.path}.tmp_encrypted');
      if (tempFile.existsSync()) tempFile.deleteSync();

      final sourceDb = raw_sqlite3.sqlite3.open(dbFile.path);
      final targetDb = raw_sqlite3.sqlite3.open(tempFile.path);
      targetDb.execute("PRAGMA key = '$key';");

      final tables = sourceDb.select("SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
      for (final row in tables) {
        final sql = row['sql'] as String?;
        if (sql != null && sql.isNotEmpty) {
          targetDb.execute(sql);
        }
      }

      targetDb.execute("ATTACH DATABASE '${dbFile.path}' AS unencrypted KEY '';");
      for (final row in tables) {
        final tableName = row['name'] as String;
        targetDb.execute("INSERT INTO main.$tableName SELECT * FROM unencrypted.$tableName;");
      }
      targetDb.execute("DETACH DATABASE unencrypted;");

      sourceDb.dispose();
      targetDb.dispose();

      dbFile.deleteSync();
      tempFile.renameSync(dbFile.path);

      // 3. Open migrated db with Drift and query record
      final executor = NativeDatabase(
        dbFile,
        setup: (db) {
          db.execute("PRAGMA key = '$key';");
        },
      );
      final migratedDb = AttentionDatabase(executor);

      final fetched = await migratedDb.notificationDao.getById('legacy_1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals('Plaintext Legacy Notification Data'));

      await migratedDb.close();

      tempDir.deleteSync(recursive: true);
    });
  });


  group('Drift Database Unit Tests', () {
    test('NotificationDao insert and lookup by ID', () async {
      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('n1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Alice'));
      expect(fetched.content, equals('Hello'));
      expect(fetched.state, equals(ReviewState.ACTIVE));
    });

    test('NotificationDao upsert behavior', () async {
      final now = DateTime.now();
      final entry1 = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      final entry2 = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello (Updated)',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry1);
      await db.notificationDao.insertNotification(entry2);

      final fetched = await db.notificationDao.getById('n1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals('Hello (Updated)'));
    });

    test('ReviewQueueDao insert, updateStatus, and delete', () async {
      final now = DateTime.now();
      final qEntry = ReviewQueueEntry(
        id: 1,
        notificationId: 'n1',
        priority: 'high',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      );

      await db.reviewQueueDao.insertItem(qEntry);

      var list = await db.reviewQueueDao.getAll();
      expect(list.length, equals(1));
      expect(list.first.priority, equals('high'));
      expect(list.first.status, equals(ReviewState.ACTIVE));

      await db.reviewQueueDao.updateStatus('n1', ReviewState.SNOOZED);
      list = await db.reviewQueueDao.getAll();
      expect(list.first.status, equals(ReviewState.SNOOZED));

      await db.reviewQueueDao.deleteItem('n1');
      list = await db.reviewQueueDao.getAll();
      expect(list, isEmpty);
    });

    test('FocusSessionDao active session tracking', () async {
      final now = DateTime.now();
      final session = FocusSessionEntry(
        id: 1,
        sessionStart: now,
        interruptions: 2,
        completion: false,
        duration: 0,
      );

      await db.focusSessionDao.insertSession(session);

      var active = await db.focusSessionDao.getActiveSession();
      expect(active, isNotNull);
      expect(active!.interruptions, equals(2));
      expect(active.completion, isFalse);

      final endedSession = session.copyWith(
        sessionEnd: Value(now.add(const Duration(minutes: 5))),
        completion: true,
        duration: 300,
      );
      await db.focusSessionDao.updateSession(endedSession);

      active = await db.focusSessionDao.getActiveSession();
      expect(active, isNull);

      final all = await db.focusSessionDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.completion, isTrue);
      expect(all.first.duration, equals(300));
    });

    test('DailyBriefDao stats increment and lookup', () async {
      final date = '2026-06-27';
      final entry = DailyBriefEntry(
        id: 1,
        date: date,
        notificationsReviewed: 5,
        actionsCompleted: 2,
        calendarEventsCreated: 1,
        remindersCreated: 1,
        archivedCount: 3,
      );

      await db.dailyBriefDao.insertOrUpdate(entry);

      var brief = await db.dailyBriefDao.getBriefForDate(date);
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, equals(5));

      await db.dailyBriefDao.incrementStats(date, reviewed: 2, completed: 1);
      brief = await db.dailyBriefDao.getBriefForDate(date);
      expect(brief!.notificationsReviewed, equals(7));
      expect(brief.actionsCompleted, equals(3));
    });

    test('NotificationDao deleteOlderThan cleanup', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      final newTime = DateTime.now().millisecondsSinceEpoch;

      final nOld = NotificationEntry(
        id: 'n-old',
        packageName: 'whatsapp',
        title: 'Old',
        content: 'Body',
        timestamp: oldTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      final nNew = NotificationEntry(
        id: 'n-new',
        packageName: 'whatsapp',
        title: 'New',
        content: 'Body',
        timestamp: newTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(nOld);
      await db.notificationDao.insertNotification(nNew);

      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final deleted = await db.notificationDao.deleteOlderThan(cutoff);
      expect(deleted, equals(1));

      final all = await db.notificationDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.id, equals('n-new'));
    });

    test('runSetBasedCleanup removes expired notifications and orphaned review queue items', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      final newTime = DateTime.now().millisecondsSinceEpoch;

      final nOld = NotificationEntry(
        id: 'n-old',
        packageName: 'whatsapp',
        title: 'Old',
        content: 'Body',
        timestamp: oldTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      final nNew = NotificationEntry(
        id: 'n-new',
        packageName: 'whatsapp',
        title: 'New',
        content: 'Body',
        timestamp: newTime,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      );

      await db.notificationDao.insertNotification(nOld);
      await db.notificationDao.insertNotification(nNew);

      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 1,
        notificationId: 'n-old',
        priority: 'high',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));
      
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 2,
        notificationId: 'n-new',
        priority: 'high',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      // This one is already orphaned before cleanup
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 3,
        notificationId: 'n-missing',
        priority: 'low',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      await db.runSetBasedCleanup(cutoff);

      final notifications = await db.notificationDao.getAll();
      expect(notifications.length, equals(1));
      expect(notifications.first.id, equals('n-new'));

      final queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      // Only the new one should remain, old one deleted due to notification expiry
      // Missing one deleted due to being orphaned
      expect(queueItems.first.notificationId, equals('n-new'));
    });
  });
}
