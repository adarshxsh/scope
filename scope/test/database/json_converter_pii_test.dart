import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('JsonConverter & DB Persistence PII Redaction Tests', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('JsonConverter.toSql redacts cleartext PII from extractedFeatures map', () {
      const converter = JsonConverter();
      final featuresMap = {
        'otp': '482910',
        'amount': 1500.00,
        'hasDeadline': false,
        'urls': ['https://bank.com/transaction/12345'],
        'emails': ['secret@domain.com'],
        'phoneNumbers': ['9876543210'],
      };

      final jsonString = converter.toSql(featuresMap);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      expect(jsonString, isNot(contains('482910')));
      expect(jsonString, isNot(contains('1500')));
      expect(jsonString, isNot(contains('secret@domain.com')));
      expect(jsonString, isNot(contains('9876543210')));

      expect(decoded['otp'], equals('[REDACTED OTP]'));
      expect(decoded['amount'], isNull);
      expect(decoded['urls'], equals(['[REDACTED URL]']));
      expect(decoded['emails'], equals(['[REDACTED EMAIL]']));
      expect(decoded['phoneNumbers'], equals(['[REDACTED PHONE]']));
    });

    test('SQLite notification entry persistence contains no cleartext OTP or amounts in extractedFeatures', () async {
      final now = DateTime.now();
      final entry = NotificationEntry(
        id: 'n_pii_test',
        packageName: 'com.bank.app',
        title: 'Debit Alert',
        content: 'Rs. 2,500 debited using OTP 987123',
        timestamp: now.millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: now,
        extractedFeatures: const {
          'otp': '987123',
          'amount': 2500.0,
          'hasDeadline': false,
          'urls': ['https://bank.com/receipt'],
          'emails': ['alert@bank.com'],
          'phoneNumbers': ['1800112233'],
        },
      );

      await db.notificationDao.insertNotification(entry);

      final fetched = await db.notificationDao.getById('n_pii_test');
      expect(fetched, isNotNull);

      final features = fetched!.extractedFeatures;
      expect(features, isNotNull);
      expect(features!['otp'], equals('[REDACTED OTP]'));
      expect(features['amount'], isNull);
      expect(features['emails'], equals(['[REDACTED EMAIL]']));
    });
  });
}
