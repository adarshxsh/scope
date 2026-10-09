import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_engine.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';

class MockBridgeWithNotifications extends NotificationBridge {
  List<AppNotification> notificationsToReturn = [];
  List<String> mockBlacklist = [];
  List<String> mockCategoryRules = [];

  @override
  Future<bool> isListenerEnabled() async => true;

  @override
  Future<List<AppNotification>> getNotifications() async => notificationsToReturn;

  @override
  Future<bool> setPackageExclusionList(List<String> packages) async {
    mockBlacklist = List.from(packages);
    return true;
  }

  @override
  Future<bool> setCategoryExclusionRules(List<String> categories) async {
    mockCategoryRules = List.from(categories);
    return true;
  }

  @override
  Future<List<String>> getPackageExclusionList() async => mockBlacklist;

  @override
  Future<List<String>> getCategoryExclusionRules() async => mockCategoryRules;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationController Pre-Persistence Privacy Gate Tests', () {
    late MockBridgeWithNotifications mockBridge;
    late InMemoryNotificationStorage storage;
    late PrivacyEngine privacyEngine;
    late NotificationController controller;

    setUp(() {
      mockBridge = MockBridgeWithNotifications();
      storage = InMemoryNotificationStorage();
      privacyEngine = PrivacyEngine();

      controller = NotificationController(
        bridge: mockBridge,
        storage: storage,
        privacyEngine: privacyEngine,
      );
    });

    test('drops blacklisted package notifications prior to storage saving', () async {
      await controller.togglePackageBlacklist('org.telegram.messenger', false);

      mockBridge.notificationsToReturn = [
        AppNotification(
          id: 't1',
          packageName: 'org.telegram.messenger',
          title: 'Secret Chat',
          content: 'Classified message',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        AppNotification(
          id: 'w1',
          packageName: 'com.whatsapp',
          title: 'Hello',
          content: 'Public message',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      await controller.fetchNotifications();

      final stored = await storage.getAll();
      expect(stored.any((n) => n.packageName == 'org.telegram.messenger'), isFalse);
      expect(stored.any((n) => n.packageName == 'com.whatsapp'), isTrue);
    });

    test('drops sensitive OTP notifications prior to storage saving when rule enabled', () async {
      await controller.setSensitiveCategoryExclusion(excludeOtpAndHealth: true);

      mockBridge.notificationsToReturn = [
        AppNotification(
          id: 'otp1',
          packageName: 'com.google.android.calendar',
          title: 'Verification Code',
          content: 'Use 352572 to verify your sign-in.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        AppNotification(
          id: 'normal1',
          packageName: 'in.amazon.mShop.android.shopping',
          title: 'Package Arriving',
          content: 'Your package is out for delivery.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      await controller.fetchNotifications();

      final stored = await storage.getAll();
      expect(stored.any((n) => n.id == 'otp1'), isFalse);
      expect(stored.any((n) => n.id == 'normal1'), isTrue);
    });
  });
}
