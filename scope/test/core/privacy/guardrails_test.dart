import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/guardrails_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late GuardrailService guardrailService;

  setUp(() async {
    db = AttentionDatabase.inMemory();
    guardrailService = GuardrailService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('GuardrailService - Category & Package Matching', () {
    test('Default state has no muted categories or excluded packages', () {
      expect(guardrailService.mutedCategories, isEmpty);
      expect(guardrailService.excludedPackages, isEmpty);
      expect(guardrailService.isCategoryMuted(SensitiveCategory.bankingOtp), isFalse);
      expect(guardrailService.isPackageExcluded('com.whatsapp'), isFalse);
    });

    test('Matches Banking & OTP category notifications', () {
      final bankNotif = AppNotification(
        id: '1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'Account Debited',
        content: 'Your account has been debited Rs. 2,000 via UPI.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        classifiedCategory: 'finance',
      );

      final otpNotif = AppNotification(
        id: '2',
        packageName: 'com.example.app',
        title: 'Your Verification Code',
        content: 'Your OTP for sign-in is 482910. Valid for 10 mins.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final regularNotif = AppNotification(
        id: '3',
        packageName: 'com.example.app',
        title: 'Weather Update',
        content: 'It will be sunny today.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(
        guardrailService.matchesCategory(bankNotif, SensitiveCategory.bankingOtp),
        isTrue,
      );
      expect(
        guardrailService.matchesCategory(otpNotif, SensitiveCategory.bankingOtp),
        isTrue,
      );
      expect(
        guardrailService.matchesCategory(regularNotif, SensitiveCategory.bankingOtp),
        isFalse,
      );
    });

    test('Matches Health category notifications', () {
      final healthNotif = AppNotification(
        id: '4',
        packageName: 'com.apollo.patientapp',
        title: 'Doctor Appointment',
        content: 'Your consultation with Dr. Smith is scheduled for 4 PM.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        classifiedCategory: 'health',
      );

      final regularNotif = AppNotification(
        id: '5',
        packageName: 'com.example.app',
        title: 'Project Update',
        content: 'The report is ready for review.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(
        guardrailService.matchesCategory(healthNotif, SensitiveCategory.health),
        isTrue,
      );
      expect(
        guardrailService.matchesCategory(regularNotif, SensitiveCategory.health),
        isFalse,
      );
    });

    test('Matches Messaging category notifications', () {
      final msgNotif = AppNotification(
        id: '6',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hey, are we still meeting today?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        category: 'msg',
      );

      final regularNotif = AppNotification(
        id: '7',
        packageName: 'com.amazon',
        title: 'Offer',
        content: '50% off on electronics.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(
        guardrailService.matchesCategory(msgNotif, SensitiveCategory.messaging),
        isTrue,
      );
      expect(
        guardrailService.matchesCategory(regularNotif, SensitiveCategory.messaging),
        isFalse,
      );
    });
  });

  group('Ingestion Guardrails & Retroactive Purge', () {
    test('Incoming notifications from muted category are dropped before AI analysis and storage', () async {
      final storage = InMemoryNotificationStorage();
      final controller = NotificationController(
        storage: storage,
        guardrails: guardrailService,
      );

      // Mute Banking/OTP category
      await controller.toggleGuardrailCategory(SensitiveCategory.bankingOtp, true);

      final otpNotif = AppNotification(
        id: 'otp-1',
        packageName: 'com.google.android.apps.authenticator',
        title: 'OTP Code',
        content: 'Your security code is 991823.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(guardrailService.shouldDrop(otpNotif), isTrue);

      // Attempt to load test data / fetch notifications
      await controller.generateTestData();

      final stored = await storage.getAll();
      final bankingOrOtpInStorage = stored.any(
        (n) => guardrailService.matchesCategory(n, SensitiveCategory.bankingOtp),
      );

      expect(bankingOrOtpInStorage, isFalse);
    });

    test('Incoming notifications from excluded package are dropped', () async {
      final storage = InMemoryNotificationStorage();
      final controller = NotificationController(
        storage: storage,
        guardrails: guardrailService,
      );

      await controller.toggleGuardrailPackage('com.whatsapp', true);

      final whatsappNotif = AppNotification(
        id: 'wa-1',
        packageName: 'com.whatsapp',
        title: 'Bob',
        content: 'Check this out!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(guardrailService.shouldDrop(whatsappNotif), isTrue);
    });

    test('Muting an app or category retroactively purges stored records within 1 second', () async {
      final storage = InMemoryNotificationStorage();
      final controller = NotificationController(
        storage: storage,
        guardrails: guardrailService,
      );

      // Save initial historical records
      final bankRecord = AppNotification(
        id: 'hist-bank-1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'Debit Alert',
        content: 'Rs. 500 debited from account.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        classifiedCategory: 'finance',
      );

      final regularRecord = AppNotification(
        id: 'hist-regular-1',
        packageName: 'com.todoist',
        title: 'Buy Groceries',
        content: 'Milk and bread',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await storage.saveAll([bankRecord, regularRecord]);
      await controller.refresh();

      expect((await storage.getAll()).length, equals(2));

      final stopwatch = Stopwatch()..start();

      // Mute Banking/OTP category
      await controller.toggleGuardrailCategory(SensitiveCategory.bankingOtp, true);

      stopwatch.stop();

      // Purge must complete within 1 second (1000 ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));

      final remaining = await storage.getAll();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('hist-regular-1'));
      expect(controller.notifications.any((n) => n.id == 'hist-bank-1'), isFalse);
    });

    test('Muting a specific app package retroactively purges historical records for that app', () async {
      final storage = InMemoryNotificationStorage();
      final controller = NotificationController(
        storage: storage,
        guardrails: guardrailService,
      );

      final waRecord1 = AppNotification(
        id: 'wa-hist-1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Call me when free',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final waRecord2 = AppNotification(
        id: 'wa-hist-2',
        packageName: 'com.whatsapp',
        title: 'Group',
        content: 'Meeting at 5 PM',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final slackRecord = AppNotification(
        id: 'slack-hist-1',
        packageName: 'com.slack',
        title: 'Boss',
        content: 'PR approved',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await storage.saveAll([waRecord1, waRecord2, slackRecord]);
      await controller.refresh();

      expect((await storage.getAll()).length, equals(3));

      // Exclude WhatsApp
      await controller.toggleGuardrailPackage('com.whatsapp', true);

      final remaining = await storage.getAll();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('slack-hist-1'));
      expect(controller.search('whatsapp'), isEmpty);
    });
  });

  group('Persistence Across Restarts', () {
    test('Muted categories and excluded packages persist across re-initialization', () async {
      // 1. First session
      await guardrailService.toggleCategory(SensitiveCategory.health, true);
      await guardrailService.togglePackage('com.facebook.katana', true);

      expect(guardrailService.isCategoryMuted(SensitiveCategory.health), isTrue);
      expect(guardrailService.isPackageExcluded('com.facebook.katana'), isTrue);

      // 2. Simulate app restart with fresh GuardrailService instance attached to same DB
      final reloadedGuardrails = GuardrailService(db);

      // Wait for settings to load from DB
      await Future.delayed(const Duration(milliseconds: 50));

      expect(reloadedGuardrails.isCategoryMuted(SensitiveCategory.health), isTrue);
      expect(reloadedGuardrails.isPackageExcluded('com.facebook.katana'), isTrue);
    });
  });
}
