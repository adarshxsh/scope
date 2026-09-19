import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/analysis/ingestion_guardrail_filter.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';

class MockNotificationBridge extends NotificationBridge {
  List<AppNotification> mockNotifications = [];

  @override
  Future<List<AppNotification>> getNotifications() async {
    final list = List<AppNotification>.from(mockNotifications);
    mockNotifications.clear();
    return list;
  }

  @override
  Future<bool> isListenerEnabled() async => true;

  @override
  Future<void> updateIngestionGuardrails(IngestionGuardrailConfig config) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationController Guardrail Integration Tests', () {
    late ProviderContainer container;
    late InMemoryNotificationStorage storage;
    late MockNotificationBridge bridge;
    late NotificationController controller;

    setUp(() {
      container = ProviderContainer();
      storage = InMemoryNotificationStorage();
      bridge = MockNotificationBridge();
      controller = NotificationController(
        container: container,
        storage: storage,
        bridge: bridge,
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    test('Excluded notifications are never stored in SQLite/Storage or review queue', () async {
      // Configure guardrails to exclude Banking & Finance and OTP
      controller.updateGuardrailConfig(
        controller.guardrailConfig.copyWith(
          excludedCategories: {
            SensitiveCategory.bankingFinance,
            SensitiveCategory.otpSecurity,
          },
          blacklistedPackages: {'com.spam.adverts'},
        ),
      );

      const bankNotif = AppNotification(
        id: 'n1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'Bank Alert',
        content: 'Account debited Rs 1000',
        timestamp: 1625097600000,
      );

      const otpNotif = AppNotification(
        id: 'n2',
        packageName: 'com.whatsapp',
        title: 'Verification Code',
        content: 'Your OTP is 881203',
        timestamp: 1625097600000,
        category: 'otp',
      );

      const spamNotif = AppNotification(
        id: 'n3',
        packageName: 'com.spam.adverts',
        title: 'Spam Offer',
        content: 'Buy now',
        timestamp: 1625097600000,
      );

      const validNotif = AppNotification(
        id: 'n4',
        packageName: 'com.google.android.gm',
        title: 'Project Update',
        content: 'The PR was approved',
        timestamp: 1625097600000,
      );

      bridge.mockNotifications = [bankNotif, otpNotif, spamNotif, validNotif];

      await controller.fetchNotifications();

      // Verify that storage contains ONLY validNotif
      final stored = await storage.getAll();
      expect(stored.length, equals(1));
      expect(stored.first.id, equals('n4'));
      expect(stored.first.packageName, equals('com.google.android.gm'));

      // Verify telemetry counts
      expect(controller.ingestionTelemetry.totalEvaluated, equals(4));
      expect(controller.ingestionTelemetry.totalIngested, equals(1));
      expect(controller.ingestionTelemetry.totalExcludedSensitiveCategory, equals(2));
      expect(controller.ingestionTelemetry.totalExcludedBlacklist, equals(1));
    });

    test('Updating Whitelist Mode dynamically filters incoming notifications', () async {
      // Enable whitelist mode with only com.slack allowed
      await controller.updateGuardrailConfig(
        controller.guardrailConfig.copyWith(
          isWhitelistModeEnabled: true,
          whitelistedPackages: {'com.slack'},
        ),
      );

      const slackNotif = AppNotification(
        id: 's1',
        packageName: 'com.slack',
        title: 'Channel Message',
        content: 'Deploying release v2.0',
        timestamp: 1625097600000,
      );

      const otherNotif = AppNotification(
        id: 'o1',
        packageName: 'com.twitter.android',
        title: 'New Follower',
        content: 'Someone followed you',
        timestamp: 1625097600000,
      );

      bridge.mockNotifications = [slackNotif, otherNotif];

      await controller.fetchNotifications();

      final stored = await storage.getAll();
      expect(stored.length, equals(1));
      expect(stored.first.packageName, equals('com.slack'));
      expect(controller.ingestionTelemetry.totalExcludedWhitelist, equals(1));
    });
  });
}
