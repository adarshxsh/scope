import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_key_manager.dart';
import 'package:scope/database/drift_notification_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Database Encryption & Key Manager Tests', () {
    late DatabaseKeyManager keyManager;

    setUp(() {
      keyManager = DatabaseKeyManager();
      keyManager.clearCache();
      DatabaseKeyManager.setOverrideKey(null);
    });

    test('DatabaseKeyManager generates a valid 256-bit key', () async {
      final key = await keyManager.getDatabaseKey();
      expect(key, isNotEmpty);
      expect(key.length, greaterThanOrEqualTo(32));
    });

    test('DatabaseKeyManager respects override key when set', () async {
      const customKey = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      DatabaseKeyManager.setOverrideKey(customKey);

      final key = await keyManager.getDatabaseKey();
      expect(key, equals(customKey));
    });

    test('AttentionDatabase returns security diagnostics and encryption status', () async {
      final db = AttentionDatabase(NativeDatabase.memory());
      final isEncrypted = await db.isEncryptedAtRest();
      expect(isEncrypted, isTrue);

      final diagnostics = await db.getSecurityDiagnostics();
      expect(diagnostics['encryptedAtRest'], isTrue);
      expect(diagnostics['keyGuardrailActive'], isTrue);
      expect(diagnostics['piiExposureCheck'], equals('passed'));
      await db.close();
    });
  });

  group('DriftNotificationStorage Validation and Capacity Guardrails', () {
    late AttentionDatabase db;
    late DriftNotificationStorage storage;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
      storage = DriftNotificationStorage(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Sanitizes text fields and strips null bytes and control characters', () async {
      final dirtyNotification = AppNotification(
        id: '  dirty_1  ',
        packageName: ' com.example.app ',
        title: 'Title\x00\x07WithNulls',
        content: 'Body\x00\x08WithControlChars',
        timestamp: 1680000000000,
      );

      await storage.save(dirtyNotification);
      final fetched = await storage.getById('dirty_1');

      expect(fetched, isNotNull);
      expect(fetched!.id, equals('dirty_1'));
      expect(fetched.packageName, equals('com.example.app'));
      expect(fetched.title, equals('TitleWithNulls'));
      expect(fetched.content, equals('BodyWithControlChars'));
    });

    test('Truncates excessively long text fields to max boundaries', () async {
      final longTitle = 'A' * 2000;
      final longContent = 'B' * 10000;

      final oversizedNotification = AppNotification(
        id: 'oversized_1',
        packageName: 'com.test.oversized',
        title: longTitle,
        content: longContent,
        timestamp: 1680000000000,
      );

      await storage.save(oversizedNotification);
      final fetched = await storage.getById('oversized_1');

      expect(fetched, isNotNull);
      expect(fetched!.title.length, equals(1000));
      expect(fetched.content.length, equals(5000));
    });

    test('Caps storage item count under peak throughput (max 500 items)', () async {
      final notifications = List.generate(
        520,
        (i) => AppNotification(
          id: 'batch_$i',
          packageName: 'com.test.batch',
          title: 'Notification $i',
          content: 'Content $i',
          timestamp: 1000000 + i,
        ),
      );

      await storage.saveAll(notifications);
      final count = await storage.count;

      expect(count, lessThanOrEqualTo(500));
    });
  });
}
