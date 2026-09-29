import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_manager.dart';
import 'package:scope/database/database_encryption_helper.dart';

void main() {
  setUp(() {
    SecureDatabaseKeyManager.resetTestStore();
  });

  group('SQLCipher Database Encryption & Secure Key Storage Tests', () {
    test('Requirement 1: SecureDatabaseKeyManager generates and stores 256-bit key', () async {
      final keyManager = SecureDatabaseKeyManager();
      final key1 = await keyManager.getOrCreatePassphrase();

      expect(key1, isNotEmpty);
      expect(key1.length, equals(64)); // 256 bits = 32 bytes = 64 hex characters
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key1), isTrue);

      final key2 = await keyManager.getOrCreatePassphrase();
      expect(key2, equals(key1));
    });

    test('Acceptance Criteria 1 & 2: Encrypted AttentionDatabase opens with passphrase and operates across all tables', () async {
      final tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_');
      final dbFile = File('${tempDir.path}/attention_os.db');
      final passphrase = SecureDatabaseKeyManager.generate256BitPassphrase();

      const sensitiveText = 'CONFIDENTIAL_NOTIFICATION_DATA_9999';
      final now = DateTime.now();

      // 1. Initialize database with passphrase
      final db = AttentionDatabase.encrypted(passphrase, file: dbFile);

      final entry = NotificationEntry(
        id: 'n-secure-1',
        packageName: 'com.bank.app',
        title: 'Bank Alert',
        content: sensitiveText,
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final brief = DailyBriefEntry(
        id: 1,
        date: '2026-09-29',
        notificationsReviewed: 10,
        actionsCompleted: 5,
        calendarEventsCreated: 2,
        remindersCreated: 1,
        archivedCount: 3,
      );
      await db.dailyBriefDao.insertOrUpdate(brief);

      await db.close();

      // 2. Verify physical file was created
      expect(dbFile.existsSync(), isTrue);

      // 3. Test SQLCipher encryption capabilities if SQLCipher is loaded in current runtime
      final testDb = sqlite3.open(dbFile.path);
      final sqlCipherSupported = DatabaseEncryptionHelper.isSqlCipherSupported(testDb);
      testDb.close();

      if (sqlCipherSupported) {
        final rawBytes = dbFile.readAsBytesSync();
        final header = String.fromCharCodes(rawBytes.take(16));
        expect(header.startsWith('SQLite format 3'), isFalse,
            reason: 'Raw SQLCipher file should not start with plain SQLite header');

        final rawContent = String.fromCharCodes(rawBytes);
        expect(rawContent.contains(sensitiveText), isFalse,
            reason: 'Raw database file must contain zero readable plaintext content');

        final unencryptedDb = sqlite3.open(dbFile.path);
        try {
          expect(
            () => unencryptedDb.select('SELECT * FROM notifications_table;'),
            throwsA(anything),
            reason: 'Raw inspection without encryption key must fail',
          );
        } finally {
          unencryptedDb.close();
        }
      }

      // 4. Re-opening with correct passphrase reads data back successfully
      final dbReopened = AttentionDatabase.encrypted(passphrase, file: dbFile);
      final fetched = await dbReopened.notificationDao.getById('n-secure-1');
      expect(fetched, isNotNull);
      expect(fetched!.content, equals(sensitiveText));

      final fetchedBrief = await dbReopened.dailyBriefDao.getBriefForDate('2026-09-29');
      expect(fetchedBrief, isNotNull);
      expect(fetchedBrief!.notificationsReviewed, equals(10));

      await dbReopened.close();
      tempDir.deleteSync(recursive: true);
    });

    test('Requirement 3 & Acceptance Criteria 3: Re-encrypts existing unencrypted database file and preserves data across all tables', () async {
      final tempDir = Directory.systemTemp.createTempSync('sqlcipher_migration_test_');
      final dbFile = File('${tempDir.path}/attention_os.db');

      const plainTextPayload = 'UNENCRYPTED_LEGACY_NOTIFICATION_BODY';
      final now = DateTime.now();

      // 1. Create legacy unencrypted database file
      final unencryptedDb = AttentionDatabase(NativeDatabase(dbFile));
      await unencryptedDb.notificationDao.insertNotification(NotificationEntry(
        id: 'legacy-1',
        packageName: 'com.whatsapp',
        title: 'Legacy Title',
        content: plainTextPayload,
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      ));

      await unencryptedDb.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 101,
        notificationId: 'legacy-1',
        priority: 'high',
        enqueueTime: now,
        status: ReviewState.ACTIVE,
      ));

      await unencryptedDb.focusSessionDao.insertSession(FocusSessionEntry(
        id: 5,
        sessionStart: now,
        interruptions: 1,
        completion: true,
        duration: 1200,
      ));

      await unencryptedDb.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 1,
        date: '2026-09-28',
        notificationsReviewed: 3,
        actionsCompleted: 1,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 1,
      ));

      await unencryptedDb.close();

      // Confirm file starts as unencrypted SQLite
      final initialBytes = dbFile.readAsBytesSync();
      final initialHeader = String.fromCharCodes(initialBytes.take(16));
      expect(initialHeader.startsWith('SQLite format 3'), isTrue);

      // 2. Perform re-encryption during update
      final passphrase = SecureDatabaseKeyManager.generate256BitPassphrase();
      await DatabaseEncryptionHelper.ensureDatabaseEncrypted(dbFile, passphrase);

      // 3. Open migrated database with AttentionDatabase using passphrase
      final encryptedDb = AttentionDatabase.encrypted(passphrase, file: dbFile);

      final fetchedNotification = await encryptedDb.notificationDao.getById('legacy-1');
      expect(fetchedNotification, isNotNull);
      expect(fetchedNotification!.content, equals(plainTextPayload));

      final queueItems = await encryptedDb.reviewQueueDao.getAll();
      expect(queueItems.length, equals(1));
      expect(queueItems.first.notificationId, equals('legacy-1'));

      final focusSessions = await encryptedDb.focusSessionDao.getAll();
      expect(focusSessions.length, equals(1));
      expect(focusSessions.first.duration, equals(1200));

      final brief = await encryptedDb.dailyBriefDao.getBriefForDate('2026-09-28');
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, equals(3));

      await encryptedDb.close();
      tempDir.deleteSync(recursive: true);
    });
  });
}
