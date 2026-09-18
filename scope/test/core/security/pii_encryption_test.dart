import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/security/pii_encryption_service.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/converters.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiiEncryptionService Tests', () {
    setUp(() async {
      await PiiEncryptionService.instance.init();
    });

    test('AES-256-GCM symmetric encryption and decryption fidelity', () {
      const plainText = 'Verification code: 882715 for Bank transaction of Rs. 5000.00';
      final cipherText = PiiEncryptionService.instance.encrypt(plainText);

      expect(cipherText, startsWith('ENC:v1:'));
      expect(cipherText, isNot(equals(plainText)));

      final decrypted = PiiEncryptionService.instance.decrypt(cipherText);
      expect(decrypted, equals(plainText));
    });

    test('Decryption handles unencrypted legacy strings gracefully', () {
      const legacyText = 'Unencrypted legacy message';
      final result = PiiEncryptionService.instance.decrypt(legacyText);
      expect(result, equals(legacyText));
    });

    test('Encryption latency is under 5 milliseconds constraint', () {
      const sampleText = 'Important security notification body with sensitive OTP 991823 and amount Rs 25000';
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 50; i++) {
        final cipher = PiiEncryptionService.instance.encrypt(sampleText);
        final plain = PiiEncryptionService.instance.decrypt(cipher);
        expect(plain, equals(sampleText));
      }
      
      stopwatch.stop();
      final avgTimeMs = stopwatch.elapsedMilliseconds / 50;
      expect(avgTimeMs, lessThan(5.0));
    });
  });

  group('Database Converter Encryption Tests', () {
    test('EncryptedTextConverter encrypts and decrypts text correctly', () {
      const converter = EncryptedTextConverter();
      const rawText = 'Sensitive OTP Notification Title';

      final sqlValue = converter.toSql(rawText);
      expect(sqlValue, startsWith('ENC:v1:'));
      expect(sqlValue, isNot(contains(rawText)));

      final restored = converter.fromSql(sqlValue);
      expect(restored, equals(rawText));
    });

    test('EncryptedJsonConverter encrypts and decrypts JSON maps correctly', () {
      const converter = EncryptedJsonConverter();
      final rawMap = {
        'otp': '882715',
        'amount': 5000.0,
        'emails': ['user@example.com'],
      };

      final sqlValue = converter.toSql(rawMap);
      expect(sqlValue, startsWith('ENC:v1:'));
      expect(sqlValue, isNot(contains('882715')));
      expect(sqlValue, isNot(contains('user@example.com')));

      final restored = converter.fromSql(sqlValue);
      expect(restored['otp'], equals('882715'));
      expect(restored['amount'], equals(5000.0));
      expect(restored['emails'], equals(['user@example.com']));
    });
  });

  group('SQLite Direct Persistence Ciphertext Inspection Tests', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('SQLite storage contains ciphertext strings for title, content, and extractedFeatures', () async {
      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'pii_test_1',
        packageName: 'com.bank.app',
        title: 'HDFC Bank Alert',
        content: 'Your account 1234 was debited Rs. 7,500. OTP is 492018.',
        timestamp: now.millisecondsSinceEpoch,
        extractedFeatures: {
          'otp': '492018',
          'amount': 7500.0,
        },
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
      );

      await db.notificationDao.insertNotification(entry);

      // 1. Verify that reading back through DAO decrypts automatically
      final fetched = await db.notificationDao.getById('pii_test_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('HDFC Bank Alert'));
      expect(fetched.content, equals('Your account 1234 was debited Rs. 7,500. OTP is 492018.'));
      expect(fetched.extractedFeatures?['otp'], equals('492018'));

      // 2. Direct SQLite query inspection to verify disk ciphertext
      final rawDb = sqlite.sqlite3.openInMemory();
      try {
        // Query low-level table rows from Drift's internal executor
        final customResult = await db.customSelect(
          'SELECT title, content, extracted_features FROM notifications_table WHERE id = ?',
          variables: [Variable.withString('pii_test_1')],
        ).getSingle();

        final rawTitle = customResult.read<String>('title');
        final rawContent = customResult.read<String>('content');
        final rawFeatures = customResult.read<String>('extracted_features');

        // Confirm fields are encrypted with prefix on disk
        expect(rawTitle, startsWith('ENC:v1:'));
        expect(rawContent, startsWith('ENC:v1:'));
        expect(rawFeatures, startsWith('ENC:v1:'));

        // Confirm raw disk data does NOT contain cleartext PII
        expect(rawTitle, isNot(contains('HDFC Bank Alert')));
        expect(rawContent, isNot(contains('7,500')));
        expect(rawContent, isNot(contains('492018')));
        expect(rawFeatures, isNot(contains('492018')));
      } finally {
        rawDb.dispose();
      }
    });
  });
}
