import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/ingestion_guardrail_controller.dart';
import 'package:scope/core/privacy/ingestion_policy.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IngestionPolicy Unit Tests', () {
    test('Drops ongoing and system noise notifications by default', () {
      const policy = IngestionPolicy(blockSystemNoise: true);

      final ongoingNotif = AppNotification(
        id: '1',
        packageName: 'com.example.app',
        title: 'Charging',
        content: '80%',
        timestamp: 1000,
        isOngoing: true,
      );

      final noiseNotif = AppNotification(
        id: '2',
        packageName: 'com.example.app',
        title: 'Downloading',
        content: 'Progress 50%',
        timestamp: 1001,
        category: 'progress',
      );

      final normalNotif = AppNotification(
        id: '3',
        packageName: 'com.example.app',
        title: 'Hello',
        content: 'World',
        timestamp: 1002,
      );

      expect(policy.shouldIngest(ongoingNotif), isFalse);
      expect(policy.shouldIngest(noiseNotif), isFalse);
      expect(policy.shouldIngest(normalNotif), isTrue);
    });

    test('Drops blacklisted package notifications', () {
      final policy = IngestionPolicy(
        blockedPackages: {'com.sensitive.bank', 'com.secret.chat'},
      );

      final blocked1 = AppNotification(
        id: '1',
        packageName: 'com.sensitive.bank',
        title: 'Account Alert',
        content: 'Statement ready',
        timestamp: 1000,
      );

      final allowed = AppNotification(
        id: '2',
        packageName: 'com.work.email',
        title: 'Meeting',
        content: 'Sync at 3pm',
        timestamp: 1001,
      );

      expect(policy.shouldIngest(blocked1), isFalse);
      expect(policy.shouldIngest(allowed), isTrue);
    });

    test('Drops excluded category notifications (Finance, Health, Social)', () {
      final policy = IngestionPolicy(
        excludedCategories: {'finance', 'social'},
      );

      final financeNotif = AppNotification(
        id: '1',
        packageName: 'com.bank.app',
        title: 'Payment Alert',
        content: 'Debited \$50',
        timestamp: 1000,
        category: 'finance',
      );

      final socialNotif = AppNotification(
        id: '2',
        packageName: 'com.social.app',
        title: 'New Like',
        content: 'John liked your photo',
        timestamp: 1001,
        category: 'social',
      );

      final healthNotif = AppNotification(
        id: '3',
        packageName: 'com.health.app',
        title: 'Step Goal',
        content: '10,000 steps reached',
        timestamp: 1002,
        category: 'health',
      );

      expect(policy.shouldIngest(financeNotif), isFalse);
      expect(policy.shouldIngest(socialNotif), isFalse);
      expect(policy.shouldIngest(healthNotif), isTrue);
    });

    test('Financial protection mode drops sensitive OTP and banking content', () {
      const policy = IngestionPolicy(financialProtectionEnabled: true);

      final otpNotif = AppNotification(
        id: '1',
        packageName: 'com.auth.app',
        title: 'Verification Code',
        content: 'Your code is 492019. Valid for 5 mins.',
        timestamp: 1000,
      );

      final bankingNotif = AppNotification(
        id: '2',
        packageName: 'com.unknown.pay',
        title: 'Money Received',
        content: '₹500 credited via UPI',
        timestamp: 1001,
      );

      final regularNotif = AppNotification(
        id: '3',
        packageName: 'com.notes.app',
        title: 'Groceries',
        content: 'Buy apples and bread',
        timestamp: 1002,
      );

      expect(policy.shouldIngest(otpNotif), isFalse);
      expect(policy.shouldIngest(bankingNotif), isFalse);
      expect(policy.shouldIngest(regularNotif), isTrue);
    });

    test('OTP masking redacts OTP codes before storage', () {
      const policy = IngestionPolicy(otpMaskingEnabled: true);

      final otpNotif = AppNotification(
        id: '1',
        packageName: 'com.service.app',
        title: 'Verification Code',
        content: 'Your login code is 882715 for signin.',
        timestamp: 1000,
      );

      final processed = policy.processBeforeIngestion(otpNotif);
      expect(processed, isNotNull);
      expect(processed!.content, contains('[REDACTED_OTP]'));
      expect(processed.content, isNot(contains('882715')));
    });

    test('Pre-ingestion policy evaluation completes in < 5ms for 50 notifications', () {
      final policy = IngestionPolicy(
        blockedPackages: {'com.blocked.app1', 'com.blocked.app2'},
        excludedCategories: {'social', 'promo'},
        otpMaskingEnabled: true,
        financialProtectionEnabled: true,
      );

      final batch = List.generate(
        50,
        (i) => AppNotification(
          id: 'notif_$i',
          packageName: i % 5 == 0 ? 'com.blocked.app1' : 'com.regular.app',
          title: 'Title $i verification code',
          content: 'Notification body $i code is 123456.',
          timestamp: 1000 + i,
          category: i % 3 == 0 ? 'social' : 'msg',
        ),
      );

      final stopwatch = Stopwatch()..start();
      final filtered = <AppNotification>[];
      for (final item in batch) {
        final res = policy.processBeforeIngestion(item);
        if (res != null) filtered.add(res);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(5));
    });
  });

  group('NotificationController Ingestion Integration Tests', () {
    late AttentionDatabase db;
    late NotificationStorage storage;

    setUp(() {
      db = AttentionDatabase.inMemory();
      storage = DriftNotificationStorage(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Excluded and blacklisted notifications leave zero trace in SQLite', () async {
      final guardrailController = IngestionGuardrailController();
      await guardrailController.updatePolicy(
        IngestionPolicy(
          blockedPackages: {'com.blacklisted.app'},
          excludedCategories: {'finance'},
        ),
      );

      final controller = NotificationController(
        storage: storage,
        guardrailController: guardrailController,
      );

      final testBatch = [
        AppNotification(
          id: 'n1',
          packageName: 'com.blacklisted.app',
          title: 'Secret',
          content: 'Payload',
          timestamp: 1000,
        ),
        AppNotification(
          id: 'n2',
          packageName: 'com.bank.app',
          title: 'Bank Statement',
          content: 'Balance update',
          timestamp: 1001,
          category: 'finance',
        ),
        AppNotification(
          id: 'n3',
          packageName: 'com.allowed.app',
          title: 'Meeting',
          content: 'Discussion at 4pm',
          timestamp: 1002,
        ),
      ];

      final allowed = guardrailController.filterBatch(testBatch);
      expect(allowed.length, equals(1));
      expect(allowed.first.id, equals('n3'));

      // Persist allowed only
      await storage.saveAll(allowed);

      final storedInDb = await storage.getAll();
      expect(storedInDb.length, equals(1));
      expect(storedInDb.first.packageName, equals('com.allowed.app'));

      // Verify zero trace of blacklisted package or finance category
      final allRows = await db.notificationDao.getAll();
      expect(allRows.any((r) => r.packageName == 'com.blacklisted.app'), isFalse);
      expect(allRows.any((r) => r.category == 'finance'), isFalse);
    });
  });
}
