import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationBridge bridge;
  late MethodChannel channel;
  late List<MethodCall> log;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.test');
    bridge = NotificationBridge(channel: channel);
    log = [];
  });

  /// Helper to set up a mock handler on the channel.
  void mockHandler(Future<dynamic> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return handler(call);
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NotificationBridge', () {
    group('getNotifications', () {
      test('returns parsed notifications from channel', () async {
        mockHandler((call) async {
          return [
            {
              'id': 'n1',
              'packageName': 'com.test.app',
              'title': 'Hello',
              'content': 'World',
              'timestamp': 1700000000000,
              'category': 'msg',
              'isOngoing': false,
            },
            {
              'id': 'n2',
              'packageName': 'com.test.app2',
              'title': 'Title 2',
              'content': 'Content 2',
              'timestamp': 1700000001000,
              'category': null,
              'isOngoing': true,
            },
          ];
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 2);
        expect(notifications[0].id, 'n1');
        expect(notifications[0].title, 'Hello');
        expect(notifications[1].id, 'n2');
        expect(notifications[1].isOngoing, true);
        expect(log.single.method, 'getNotifications');
      });

      test('returns empty list when channel returns null', () async {
        mockHandler((call) async => null);
        final notifications = await bridge.getNotifications();
        expect(notifications, isEmpty);
      });

      test('returns empty list when channel returns empty list', () async {
        mockHandler((call) async => <Map>[]);
        final notifications = await bridge.getNotifications();
        expect(notifications, isEmpty);
      });

      test('returns empty list on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'test error');
        });
        final notifications = await bridge.getNotifications();
        expect(notifications, isEmpty);
      });
    });

    group('peekNotifications', () {
      test('returns parsed notifications from channel without draining', () async {
        mockHandler((call) async {
          return [
            {
              'id': 'n1',
              'packageName': 'com.test.app',
              'title': 'Hello Peek',
              'content': 'World Peek',
              'timestamp': 1700000000000,
              'category': 'msg',
              'isOngoing': false,
            },
          ];
        });

        final notifications = await bridge.peekNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].id, 'n1');
        expect(notifications[0].title, 'Hello Peek');
        expect(log.single.method, 'peekNotifications');
      });

      test('returns empty list when channel returns null', () async {
        mockHandler((call) async => null);
        final notifications = await bridge.peekNotifications();
        expect(notifications, isEmpty);
      });

      test('returns empty list on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'peek failed');
        });
        final notifications = await bridge.peekNotifications();
        expect(notifications, isEmpty);
      });
    });

    group('acknowledgeNotifications', () {
      test('invokes acknowledgeNotifications channel method with ids map', () async {
        mockHandler((call) async => true);

        await bridge.acknowledgeNotifications(['n1', 'n2']);
        expect(log.single.method, 'acknowledgeNotifications');
        expect(log.single.arguments, {'ids': ['n1', 'n2']});
      });

      test('does nothing when ids list is empty', () async {
        await bridge.acknowledgeNotifications([]);
        expect(log, isEmpty);
      });

      test('does not throw on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'ack failed');
        });
        await bridge.acknowledgeNotifications(['n1']);
        expect(log.single.method, 'acknowledgeNotifications');
      });
    });

    group('Peek-and-Acknowledge Protocol', () {
      test('queue items remain in memory after peeking and disappear only after acknowledgment', () async {
        final mockNativeQueue = <Map<String, dynamic>>[
          {
            'id': 'n1',
            'packageName': 'com.test.one',
            'title': 'First',
            'content': 'Item 1',
            'timestamp': 1000,
            'category': 'msg',
            'isOngoing': false,
          },
          {
            'id': 'n2',
            'packageName': 'com.test.two',
            'title': 'Second',
            'content': 'Item 2',
            'timestamp': 2000,
            'category': 'msg',
            'isOngoing': false,
          },
        ];

        mockHandler((call) async {
          switch (call.method) {
            case 'peekNotifications':
              return List<Map<String, dynamic>>.from(mockNativeQueue);
            case 'acknowledgeNotifications':
              final map = call.arguments as Map<dynamic, dynamic>?;
              final ids = (map?['ids'] as List?)?.cast<String>() ?? [];
              mockNativeQueue.removeWhere((item) => ids.contains(item['id']));
              return true;
            default:
              return null;
          }
        });

        // 1. Initial peek: both items returned, queue size remains 2
        var peek1 = await bridge.peekNotifications();
        expect(peek1.length, 2);
        expect(mockNativeQueue.length, 2);

        // 2. Second peek without ack: state unchanged
        var peek2 = await bridge.peekNotifications();
        expect(peek2.length, 2);
        expect(mockNativeQueue.length, 2);

        // 3. Acknowledge 'n1': queue size becomes 1
        await bridge.acknowledgeNotifications(['n1']);
        expect(mockNativeQueue.length, 1);
        expect(mockNativeQueue[0]['id'], 'n2');

        // 4. Peek after ack: only 'n2' returned
        var peek3 = await bridge.peekNotifications();
        expect(peek3.length, 1);
        expect(peek3[0].id, 'n2');

        // 5. Acknowledge 'n2': queue becomes empty
        await bridge.acknowledgeNotifications(['n2']);
        expect(mockNativeQueue, isEmpty);

        // 6. Peek empty queue: returns empty
        var peek4 = await bridge.peekNotifications();
        expect(peek4, isEmpty);
      });
    });

    group('isListenerEnabled', () {
      test('returns true when channel returns true', () async {
        mockHandler((call) async => true);
        final result = await bridge.isListenerEnabled();
        expect(result, true);
        expect(log.single.method, 'isListenerEnabled');
      });

      test('returns false when channel returns false', () async {
        mockHandler((call) async => false);
        final result = await bridge.isListenerEnabled();
        expect(result, false);
      });

      test('returns false when channel returns null', () async {
        mockHandler((call) async => null);
        final result = await bridge.isListenerEnabled();
        expect(result, false);
      });

      test('returns false on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR');
        });
        final result = await bridge.isListenerEnabled();
        expect(result, false);
      });
    });

    group('openNotificationSettings', () {
      test('invokes correct method on channel', () async {
        mockHandler((call) async => true);
        await bridge.openNotificationSettings();
        expect(log.single.method, 'openNotificationSettings');
      });

      test('does not throw on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR');
        });
        // Should complete without throwing
        await bridge.openNotificationSettings();
      });
    });
  });
}
