import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';

void main() {
  late AttentionDatabase db;
  late DriftNotificationStorage storage;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
    storage = DriftNotificationStorage(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift Database PII Storage Tests', () {
    test('automatically redacts PII before persisting to SQLite database', () async {
      final rawNotif = AppNotification(
        id: 'pii_db_1',
        packageName: 'com.whatsapp',
        title: 'Verification code',
        content: 'Your code is 882715.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: {
          'otp': '882715',
          'phoneNumbers': ['+18005550199'],
        },
      );

      await storage.save(rawNotif);

      final fetched = await storage.getById('pii_db_1');
      expect(fetched, isNotNull);
      expect(fetched!.content, contains('[REDACTED CODE]'));
      expect(fetched.content, isNot(contains('882715')));
      expect(fetched.extractedFeatures!['otp'], equals('[REDACTED CODE]'));
      expect(fetched.extractedFeatures!['phoneNumbers'], equals(['[REDACTED PHONE]']));
    });
  });
}
