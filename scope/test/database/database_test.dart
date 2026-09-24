import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  setUpAll(() {
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

  group('SQLCipher Encryption & Migration Tests', () {
    late Directory tempDir;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('getOrCreatePassphrase creates 256-bit hex key in secure storage', () async {
      const storage = FlutterSecureStorage();
      final key = await getOrCreatePassphrase(storage);
      expect(key, isNotEmpty);
      expect(key.length, equals(64)); // 32 bytes = 64 hex characters

      final storedKey = await storage.read(key: 'attention_db_passphrase');
      expect(storedKey, equals(key));
    });

    test('openConnectionForFile encrypts new database file', () async {
      const storage = FlutterSecureStorage();
      final dbFile = File('${tempDir.path}/encrypted_test.db');
      
      final executor = await openConnectionForFile(dbFile, storage: storage);
      final encDb = AttentionDatabase(executor);
      
      final now = DateTime.now();
      await encDb.notificationDao.insertNotification(NotificationEntry(
        id: 'sec1',
        packageName: 'com.secret',
        title: 'Confidential',
        content: 'OTP 123456',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      final fetched = await encDb.notificationDao.getById('sec1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals('OTP 123456'));

      await encDb.close();

      // Attempting to open encrypted DB file directly with standard sqlite3 without PRAGMA key fails
      final rawDb = sqlite3.open(dbFile.path);
      expect(
        () => rawDb.execute('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      rawDb.dispose();

      // Opening with PRAGMA key succeeds
      final key = await storage.read(key: 'attention_db_passphrase');
      final keyedDb = sqlite3.open(dbFile.path);
      keyedDb.execute("PRAGMA key = '$key';");
      final result = keyedDb.select('SELECT title FROM notifications_table WHERE id = ?;', ['sec1']);
      expect(result.first['title'], equals('Confidential'));
      keyedDb.dispose();
    });

    test('isUnencryptedSqlite correctly identifies unencrypted vs encrypted files', () async {
      final unencryptedFile = File('${tempDir.path}/plain.db');
      final rawDb = sqlite3.open(unencryptedFile.path);
      rawDb.execute('CREATE TABLE dummy (id INTEGER);');
      rawDb.dispose();

      expect(await isUnencryptedSqlite(unencryptedFile), isTrue);

      const storage = FlutterSecureStorage();
      final encryptedFile = File('${tempDir.path}/enc.db');
      final executor = await openConnectionForFile(encryptedFile, storage: storage);
      final encDb = AttentionDatabase(executor);
      await encDb.customSelect('SELECT 1').get();
      await encDb.close();

      expect(await isUnencryptedSqlite(encryptedFile), isFalse);
    });

    test('upgrading existing unencrypted database converts file without losing rows', () async {
      final dbFile = File('${tempDir.path}/legacy_os.db');
      
      // Step 1: Create legacy unencrypted SQLite database
      final rawLegacyDb = sqlite3.open(dbFile.path);
      rawLegacyDb.execute('''
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
      rawLegacyDb.execute('''
        INSERT INTO notifications_table (id, package_name, title, content, timestamp, state, reviewed, dismissed, is_ongoing, created_at)
        VALUES ('legacy1', 'com.app', 'Legacy Title', 'Secret Message', 1000, 'ACTIVE', 0, 0, 0, 1000);
      ''');
      rawLegacyDb.dispose();

      expect(await isUnencryptedSqlite(dbFile), isTrue);

      // Step 2: Open using openConnectionForFile (triggers rekey migration)
      const storage = FlutterSecureStorage();
      final executor = await openConnectionForFile(dbFile, storage: storage);
      final migratedDb = AttentionDatabase(executor);

      // Step 3: Verify data was preserved
      final fetched = await migratedDb.notificationDao.getById('legacy1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Legacy Title'));
      expect(fetched.content, equals('Secret Message'));

      await migratedDb.close();

      // Step 4: Verify file on disk is now encrypted and starts with encrypted pages (isUnencryptedSqlite returns false)
      expect(await isUnencryptedSqlite(dbFile), isFalse);

      final plainDbAttempt = sqlite3.open(dbFile.path);
      expect(
        () => plainDbAttempt.execute('SELECT * FROM notifications_table;'),
        throwsA(isA<SqliteException>()),
      );
      plainDbAttempt.dispose();
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
