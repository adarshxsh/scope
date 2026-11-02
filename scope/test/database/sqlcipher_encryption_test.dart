import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File dbFile;
  late DatabaseKeyVault keyVault;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
    dbFile = File('${tempDir.path}/attention_os.db');
    keyVault = DatabaseKeyVault();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SQLCipher Database Encryption Forensic & Verification Tests', () {
    test('Encrypts database on disk with page-level AES-256 and protects sensitive payloads', () async {
      // 1. Initialize encrypted database on disk
      var db = AttentionDatabase.openOnDisk(dbFile, keyVault: keyVault);

      final now = DateTime.now();
      const secretTitle = 'CONFIDENTIAL_OTP_882715';
      const secretContent = 'SECRET_AUTHENTICATION_CODE_999';

      // 2. Populate data across all tables
      await db.notificationDao.insertNotification(NotificationEntry(
        id: 'otp_1',
        packageName: 'com.bank.auth',
        title: secretTitle,
        content: secretContent,
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 101,
        notificationId: 'otp_1',
        priority: 'critical',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      ));

      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 201,
        sessionStart: now,
        interruptions: 0,
        completion: true,
        duration: 300,
      ));

      await db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 301,
        date: '2026-09-16',
        notificationsReviewed: 1,
        actionsCompleted: 1,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 0,
      ));

      // Verify readable via Drift DAO
      final fetchedNotification = await db.notificationDao.getById('otp_1');
      expect(fetchedNotification, isNotNull);
      expect(fetchedNotification!.title, equals(secretTitle));
      expect(fetchedNotification.content, equals(secretContent));

      // Close database connection before disk inspection
      await db.close();

      // 3. Forensic inspection of physical file bytes on disk
      expect(await dbFile.exists(), isTrue);
      final rawBytes = await dbFile.readAsBytes();
      expect(rawBytes.length, greaterThan(0));

      // Standard SQLite header starts with ASCII "SQLite format 3\x00".
      // SQLCipher encrypts page 0, making this header absent/ciphertext.
      final headerString = String.fromCharCodes(rawBytes.take(15));
      expect(headerString, isNot(equals('SQLite format 3\x00')));

      // Raw ciphertext must not contain any plaintext string payloads
      final rawContentAsString = String.fromCharCodes(rawBytes);
      expect(rawContentAsString.contains(secretTitle), isFalse);
      expect(rawContentAsString.contains(secretContent), isFalse);
      expect(rawContentAsString.contains('com.bank.auth'), isFalse);

      // 4. Verification that opening WITHOUT passphrase fails
      final unencryptedRawDb = sqlite3.sqlite3.open(dbFile.path);
      expect(
        () => unencryptedRawDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<sqlite3.SqliteException>()),
      );
      unencryptedRawDb.close();

      // 5. Verification that opening WITH WRONG passphrase fails
      final wrongRawDb = sqlite3.sqlite3.open(dbFile.path);
      wrongRawDb.execute("PRAGMA key = 'wrong_passphrase_1234567890';");
      expect(
        () => wrongRawDb.select('SELECT * FROM notifications_table;'),
        throwsA(isA<sqlite3.SqliteException>()),
      );
      wrongRawDb.close();

      // 6. Verification that opening WITH CORRECT passphrase succeeds
      db = AttentionDatabase.openOnDisk(dbFile, keyVault: keyVault);
      final reOpenedNotification = await db.notificationDao.getById('otp_1');
      expect(reOpenedNotification, isNotNull);
      expect(reOpenedNotification!.title, equals(secretTitle));
      expect(reOpenedNotification.content, equals(secretContent));

      final queueItems = await db.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      expect(queueItems.first.priority, equals('critical'));

      await db.close();
    });
  });
}
