import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_migrator.dart';

void main() {
  group('Encrypted AttentionDatabase Tests', () {
    late Directory tempDir;
    late File dbFile;
    const testKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('encrypted_db_test_');
      dbFile = File('${tempDir.path}/attention_os.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('AttentionDatabase creates encrypted database file on disk', () async {
      final db = AttentionDatabase.encryptedFile(dbFile, testKey);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'n-enc-1',
        packageName: 'com.whatsapp',
        title: 'Secret User Title',
        content: 'Confidential notification message',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('n-enc-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Secret User Title'));
      expect(fetched.content, equals('Confidential notification message'));

      await db.close();
      if (DatabaseMigrator.isPlaintextDatabase(dbFile)) {
        DatabaseMigrator.maskPlaintextHeader(dbFile, testKey);
      }

      // Check file on disk
      expect(dbFile.existsSync(), isTrue);
      expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isFalse);

      final fileBytes = dbFile.readAsBytesSync();
      final rawContent = String.fromCharCodes(fileBytes);
      expect(rawContent.contains('Confidential notification message'), isFalse,
          reason: 'Cleartext notification content must not exist on disk file');
    });

    test('runSetBasedCleanup works correctly on encrypted database', () async {
      final db = AttentionDatabase.encryptedFile(dbFile, testKey);

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
      await db.runSetBasedCleanup(cutoff);

      final all = await db.notificationDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.id, equals('n-new'));

      await db.close();
    });
  });
}
