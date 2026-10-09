import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';

class SlowMockBridge extends NotificationBridge {
  int fetchCallCount = 0;
  List<AppNotification> returnList = [];

  @override
  Future<List<AppNotification>> getNotifications() async {
    fetchCallCount++;
    await Future.delayed(const Duration(milliseconds: 50));
    return returnList;
  }

  @override
  Future<bool> isListenerEnabled() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Polling Guardrails & Adaptive Execution Tests', () {
    late ProviderContainer container;
    late SlowMockBridge mockBridge;
    late InMemoryNotificationStorage mockStorage;
    late NotificationController controller;

    setUp(() {
      container = ProviderContainer();
      mockBridge = SlowMockBridge();
      mockStorage = InMemoryNotificationStorage();
      controller = NotificationController(
        bridge: mockBridge,
        storage: mockStorage,
        container: container,
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    test('reentrancy lock prevents concurrent fetchNotifications execution', () async {
      mockBridge.returnList = [];

      // Trigger two concurrent fetch calls
      final future1 = controller.fetchNotifications();
      final future2 = controller.fetchNotifications();

      await Future.wait([future1, future2]);

      // Only 1 fetch call should have actually executed on bridge
      expect(mockBridge.fetchCallCount, equals(1));
    });

    test('sanitizes oversized raw notification inputs during fromMap', () {
      final oversizedTitle = 'A' * 500;
      final oversizedContent = 'B' * 3000;

      final rawMap = {
        'id': 'over_1',
        'packageName': '  com.test.app  ',
        'title': oversizedTitle,
        'content': oversizedContent,
        'timestamp': -100,
      };

      final notif = AppNotification.fromMap(rawMap);

      expect(notif.packageName, equals('com.test.app'));
      expect(notif.title.length, equals(300));
      expect(notif.content.length, equals(2000));
      expect(notif.timestamp, greaterThan(0));
    });

    test('refresh resets adaptive polling state and re-fetches', () async {
      mockBridge.returnList = [];
      await controller.refresh();

      expect(mockBridge.fetchCallCount, greaterThan(0));
    });
  });
}
