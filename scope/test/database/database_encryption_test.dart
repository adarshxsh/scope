import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/database_key_manager.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/converters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Database Storage Encryption at Rest Guardrails', () {
    test('DatabaseKeyManager generates and retrieves valid 256-bit passphrase key', () async {
      final keyManager = DatabaseKeyManager();
      final key = await keyManager.getOrCreateKey();

      expect(key, isNotEmpty);
      expect(key.length, greaterThanOrEqualTo(32));
    });

    test('JsonConverter encrypts extractedFeatures with ENC: prefix and decrypts successfully', () {
      const converter = JsonConverter();
      final originalData = {
        'otp_code': '882715',
        'amount': 1500.0,
        'contains_pii': true,
        'category': 'finance',
      };

      final serialized = converter.toSql(originalData);
      expect(serialized, startsWith('ENC:'));
      expect(serialized, isNot(contains('882715')));

      final deserialized = converter.fromSql(serialized);
      expect(deserialized['otp_code'], equals('882715'));
      expect(deserialized['amount'], equals(1500.0));
      expect(deserialized['contains_pii'], isTrue);
    });

    test('JsonConverter seamlessly handles legacy unencrypted JSON strings', () {
      const converter = JsonConverter();
      const legacyJson = '{"title":"Legacy Alert","score":85}';

      final result = converter.fromSql(legacyJson);
      expect(result['title'], equals('Legacy Alert'));
      expect(result['score'], equals(85));
    });

    test('JsonConverter safely handles corrupt payload and returns empty map without throwing', () {
      const converter = JsonConverter();
      const corruptPayload = 'ENC:invalid_base64_and_corrupt_data!!!';

      expect(() => converter.fromSql(corruptPayload), returnsNormally);
      final result = converter.fromSql(corruptPayload);
      expect(result, isEmpty);
    });

    test('verifyEncryptionAtRest detects plain text vs encrypted database file headers', () async {
      final tempDir = await Directory.systemTemp.createTemp('db_enc_test');
      
      // Plain text SQLite database header
      final plainDbFile = File('${tempDir.path}/plain.db');
      final plainHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
      await plainDbFile.writeAsBytes(plainHeader);

      final isPlainEncrypted = await AttentionDatabase.verifyEncryptionAtRest(plainDbFile);
      expect(isPlainEncrypted, isFalse, reason: 'Plain text SQLite file header should be identified as unencrypted');

      // Encrypted database header (random cipher bytes)
      final encryptedDbFile = File('${tempDir.path}/encrypted.db');
      final encryptedHeader = List<int>.generate(16, (i) => (i * 37 + 13) % 256);
      await encryptedDbFile.writeAsBytes(encryptedHeader);

      final isHeaderEncrypted = await AttentionDatabase.verifyEncryptionAtRest(encryptedDbFile);
      expect(isHeaderEncrypted, isTrue, reason: 'Encrypted header bytes should be verified as encrypted');

      await tempDir.delete(recursive: true);
    });

    test('AttentionDatabase enforceQuotaLimits truncates excess entries when exceeding max threshold', () async {
      final db = AttentionDatabase.inMemory();

      final now = DateTime.now();
      for (var i = 0; i < 10; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'quota_n_$i',
          packageName: 'com.test',
          title: 'Notification $i',
          content: 'Content',
          timestamp: now.millisecondsSinceEpoch + i,
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: now,
        ));
      }

      final countBefore = await db.notificationDao.getCount();
      expect(countBefore, equals(10));

      final deleted = await db.enforceQuotaLimits(maxCount: 7);
      expect(deleted, equals(3));

      final countAfter = await db.notificationDao.getCount();
      expect(countAfter, equals(7));

      // Oldest notifications (indices 0, 1, 2) should be removed
      final fetchedOldest = await db.notificationDao.getById('quota_n_0');
      expect(fetchedOldest, isNull);

      final fetchedNewest = await db.notificationDao.getById('quota_n_9');
      expect(fetchedNewest, isNotNull);

      await db.close();
    });
  });
}
