import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/notification_detail_screen.dart';

class MockNotificationBridge extends NotificationBridge {
  List<AppNotification> mockNotifications = [];

  @override
  Future<List<AppNotification>> getNotifications() async {
    return mockNotifications;
  }

  @override
  Future<bool> isListenerEnabled() async => true;
}

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PII Redaction Pipeline Tests', () {
    late InMemoryNotificationStorage storage;
    late MockNotificationBridge bridge;
    late ProviderContainer container;
    late NotificationController controller;

    setUp(() {
      storage = InMemoryNotificationStorage();
      bridge = MockNotificationBridge();
      container = ProviderContainer();
      controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: FakeGhostAnalysisEngine(),
        container: container,
      );
    });

    tearDown(() {
      container.dispose();
      controller.dispose();
    });

    test('Runs feature extraction on raw text before redacting in-memory state', () async {
      final rawNotification = AppNotification(
        id: 'pii_test_1',
        packageName: 'com.bank.app',
        title: 'Payment Alert for user@example.com',
        content: 'Your OTP is 654321 for transaction of \$150.00 using card 4111 2222 3333 4444',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      bridge.mockNotifications = [rawNotification];
      await controller.fetchNotifications();

      // 1. In-memory notification model in controller and Riverpod state is redacted
      expect(controller.notifications, isNotEmpty);
      final inMemoryNotif = controller.notifications.first;

      expect(inMemoryNotif.title, contains('[REDACTED_EMAIL]'));
      expect(inMemoryNotif.content, contains('[REDACTED_OTP]'));
      expect(inMemoryNotif.content, contains('[REDACTED_AMOUNT]'));
      expect(inMemoryNotif.content, contains('[REDACTED_CARD]'));

      final riverpodNotif = container.read(reviewQueueProvider).first;
      expect(riverpodNotif.title, contains('[REDACTED_EMAIL]'));
      expect(riverpodNotif.content, contains('[REDACTED_OTP]'));
      expect(riverpodNotif.content, contains('[REDACTED_AMOUNT]'));
      expect(riverpodNotif.content, contains('[REDACTED_CARD]'));

      // 2. Feature extraction ran on raw text prior to redaction
      final features = inMemoryNotif.extractedFeatures;
      expect(features, isNotNull);
      expect(features?['amount'], equals(150.00));
      expect(features?['emails'], contains('user@example.com'));
      expect(features?['otp'], equals('654321'));
    });

    test('In-memory duplicate checking operates on sanitized instances', () async {
      final rawNotification1 = AppNotification(
        id: 'pii_dup_1',
        packageName: 'com.finance.app',
        title: 'Balance update',
        content: 'Your passcode is 1234',
        timestamp: 1700000000000,
      );

      bridge.mockNotifications = [rawNotification1];
      await controller.fetchNotifications();

      expect(controller.notifications.length, equals(1));
      expect(controller.notifications.first.content, contains('[REDACTED_OTP]'));

      // Fetch duplicate notification
      final rawNotification2 = AppNotification(
        id: 'pii_dup_2',
        packageName: 'com.finance.app',
        title: 'Balance update',
        content: 'Your passcode is 1234',
        timestamp: 1700000000000,
      );

      bridge.mockNotifications = [rawNotification2];
      await controller.fetchNotifications();

      // Should not add duplicate
      expect(controller.notifications.length, equals(1));
    });

    test('Detail view fetches unredacted payload on demand from storage', () async {
      final rawNotification = AppNotification(
        id: 'pii_detail_1',
        packageName: 'com.shopping.app',
        title: 'Order confirmation for john@company.org',
        content: 'Call +1 555 123 4567 for total Rs. 2500',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      bridge.mockNotifications = [rawNotification];
      await controller.fetchNotifications();

      final sanitizedInMemory = controller.notifications.first;
      expect(sanitizedInMemory.title, contains('[REDACTED_EMAIL]'));
      expect(sanitizedInMemory.content, contains('[REDACTED_PHONE]'));
      expect(sanitizedInMemory.content, contains('[REDACTED_AMOUNT]'));

      // Fetch unredacted on demand from controller/storage
      final unredacted = await controller.getUnredactedNotification(sanitizedInMemory.id);
      expect(unredacted, isNotNull);
      expect(unredacted!.title, equals('Order confirmation for john@company.org'));
      expect(unredacted.content, equals('Call +1 555 123 4567 for total Rs. 2500'));
    });

    testWidgets('NotificationDetailScreen loads unredacted text asynchronously on demand', (WidgetTester tester) async {
      final rawNotification = AppNotification(
        id: 'pii_screen_1',
        packageName: 'com.auth.service',
        title: 'Login OTP',
        content: 'Your login code is 876543 for contact contact@domain.com',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await storage.save(rawNotification);

      final sanitizedInMemory = rawNotification.copyWith(
        title: 'Login OTP',
        content: 'Your login code is [REDACTED_OTP] for contact [REDACTED_EMAIL]',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationDetailScreen(
            notification: sanitizedInMemory,
            controller: controller,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Your login code is 876543 for contact contact@domain.com'), findsOneWidget);
    });
  });
}
