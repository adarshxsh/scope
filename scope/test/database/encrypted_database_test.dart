import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('Encrypted AttentionDatabase Tests', () {
    test('AttentionDatabase initializes and executes queries with passphrase setup', () async {
      const passphrase = 'test_secret_passphrase_256_bit_derived_key';

      final executor = NativeDatabase.memory(
        setup: (db) {
          db.execute("PRAGMA key = '$passphrase';");
        },
      );

      final db = AttentionDatabase(executor);

      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'enc-1',
        packageName: 'com.signal.app',
        title: 'Encrypted Message',
        content: 'Top secret content',
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
      expect(fetched.content, equals('Top secret content'));

      await db.close();
    });
  });
}
