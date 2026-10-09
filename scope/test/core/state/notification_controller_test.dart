import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';

class MockBridge extends NotificationBridge {
  @override
  Future<bool> isListenerEnabled() async => true;

  @override
  Future<List<AppNotification>> getNotifications() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationController Dev Tools Guard Tests', () {
    late NotificationController controller;
    late InMemoryNotificationStorage storage;

    setUp(() {
      storage = InMemoryNotificationStorage();
      controller = NotificationController(
        bridge: MockBridge(),
        storage: storage,
        container: ProviderContainer(),
      );
    });

    test('generateTestData and clearAll operate when kDebugMode is true', () async {
      if (kDebugMode) {
        expect(controller.notifications, isEmpty);

        await controller.generateTestData();
        expect(controller.notifications.isNotEmpty, isTrue);

        await controller.clearAll();
        expect(controller.notifications, isEmpty);
      }
    });
  });
}
