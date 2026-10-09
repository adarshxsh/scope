import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Queue Guardrail Simulation Tests', () {
    late MethodChannel channel;
    late NotificationBridge bridge;
    late List<Map<String, dynamic>> mockNativeQueue;
    const maxCapacity = 500;

    setUp(() {
      channel = const MethodChannel('com.scope.notifications.test');
      bridge = NotificationBridge(channel: channel);
      mockNativeQueue = [];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getNotifications':
            final drained = List<Map<String, dynamic>>.from(mockNativeQueue);
            mockNativeQueue.clear();
            return drained;
          case 'getQueueSize':
            return mockNativeQueue.length;
          case 'clearQueue':
            mockNativeQueue.clear();
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void simulateIncomingNativeSbn({
      required String id,
      required String packageName,
      required String title,
      required String content,
      required int timestamp,
      bool isOngoing = false,
    }) {
      final isDuplicate = mockNativeQueue.any((item) =>
          item['packageName'] == packageName &&
          item['title'] == title &&
          item['content'] == content);

      if (isDuplicate) return;

      while (mockNativeQueue.length >= maxCapacity) {
        mockNativeQueue.removeAt(0); // Evict oldest FIFO
      }

      mockNativeQueue.add({
        'id': id,
        'packageName': packageName,
        'title': title,
        'content': content,
        'timestamp': timestamp,
        'category': 'msg',
        'isOngoing': isOngoing,
      });
    }

    test('enforces max queue capacity of 500 by evicting oldest items', () async {
      // Simulate pushing 600 notifications without draining
      for (int i = 1; i <= 600; i++) {
        simulateIncomingNativeSbn(
          id: 'notif_$i',
          packageName: 'com.test.app',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: 1000 + i,
        );
      }

      final size = await bridge.getQueueSize();
      expect(size, equals(500));

      final notifications = await bridge.getNotifications();
      expect(notifications.length, equals(500));
      // First item remaining should be notification 101 because 1..100 were evicted
      expect(notifications.first.title, equals('Title 101'));
      expect(notifications.last.title, equals('Title 600'));
    });

    test('suppresses duplicate notifications in native queue', () async {
      simulateIncomingNativeSbn(
        id: 'notif_1',
        packageName: 'com.chat.app',
        title: 'New Message',
        content: 'Hello!',
        timestamp: 1000,
      );

      // Same message posted again
      simulateIncomingNativeSbn(
        id: 'notif_2',
        packageName: 'com.chat.app',
        title: 'New Message',
        content: 'Hello!',
        timestamp: 1005,
      );

      final size = await bridge.getQueueSize();
      expect(size, equals(1));

      final notifications = await bridge.getNotifications();
      expect(notifications.length, equals(1));
      expect(notifications.first.title, equals('New Message'));
      expect(notifications.first.content, equals('Hello!'));
    });

    test('drainQueue empties native queue atomically', () async {
      for (int i = 1; i <= 10; i++) {
        simulateIncomingNativeSbn(
          id: 'notif_$i',
          packageName: 'com.test.app',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: 1000 + i,
        );
      }

      expect(await bridge.getQueueSize(), equals(10));
      final notifications = await bridge.getNotifications();
      expect(notifications.length, equals(10));

      // Subsequent drain call returns empty list
      expect(await bridge.getQueueSize(), equals(0));
      final emptyCheck = await bridge.getNotifications();
      expect(emptyCheck, isEmpty);
    });

    test('clearQueue purges all items from queue', () async {
      simulateIncomingNativeSbn(
        id: 'notif_1',
        packageName: 'com.test.app',
        title: 'Title',
        content: 'Content',
        timestamp: 1000,
      );

      expect(await bridge.getQueueSize(), equals(1));
      final cleared = await bridge.clearQueue();
      expect(cleared, isTrue);
      expect(await bridge.getQueueSize(), equals(0));
    });
  });
}
