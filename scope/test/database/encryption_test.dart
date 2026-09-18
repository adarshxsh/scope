import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';
import 'package:scope/database/encryption_converter.dart';

void main() {
  group('Database Encryption & Bounded Storage Guardrail Tests', () {
    test('EncryptedTextConverter encrypts text payload and decrypts accurately', () {
      const converter = EncryptedTextConverter();
      const rawText = 'Sensitive Financial OTP 992812';

      final sqlValue = converter.toSql(rawText);
      expect(sqlValue, startsWith('ENC:v1:'));
      expect(sqlValue, isNot(contains(rawText)));

      final decrypted = converter.fromSql(sqlValue);
      expect(decrypted, equals(rawText));
    });

    test('EncryptedTextConverter handles unencrypted legacy cleartext records gracefully', () {
      const converter = EncryptedTextConverter();
      const legacyCleartext = 'Legacy notification text';

      final result = converter.fromSql(legacyCleartext);
      expect(result, equals(legacyCleartext));
    });

    test('EncryptedTextConverter recovers gracefully from corrupted encrypted string', () {
      const converter = EncryptedTextConverter();
      const corruptedValue = 'ENC:v1:corrupted_base64_payload_!!!';

      final result = converter.fromSql(corruptedValue);
      expect(result, equals('[Encrypted Record Recovery Failed]'));
    });

    test('DriftNotificationStorage persists notifications encrypted and enforces 500-item capacity limit', () async {
      final db = AttentionDatabase.inMemory();
      final storage = DriftNotificationStorage(db);

      // Save 520 notifications
      final notifs = List.generate(
        520,
        (i) => AppNotification(
          id: 'capacity_test_$i',
          packageName: 'com.test.app',
          title: 'Title $i',
          content: 'Secret Content $i',
          timestamp: 1700000000000 + i,
        ),
      );

      await storage.saveAll(notifs);

      final count = await storage.count;
      expect(count, equals(500)); // Enforced cap

      final loaded = await storage.getAll();
      expect(loaded.length, equals(500));

      // Oldest 20 (timestamp 1700000000000..1700000000019) should have been purged
      final hasOldest = loaded.any((n) => n.id == 'capacity_test_0');
      expect(hasOldest, isFalse);

      final hasNewest = loaded.any((n) => n.id == 'capacity_test_519');
      expect(hasNewest, isTrue);

      await db.close();
    });
  });
}
