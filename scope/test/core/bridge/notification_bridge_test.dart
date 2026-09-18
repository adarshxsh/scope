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
    bridge = NotificationBridge(
      channel: channel,
      sessionToken: 'test-session-token',
    );
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
      test('returns parsed notifications from channel map with batchId', () async {
        mockHandler((call) async {
          expect(call.arguments['token'], 'test-session-token');
          return {
            'batchId': 'batch_123',
            'notifications': [
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
            ],
          };
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 2);
        expect(notifications[0].id, 'n1');
        expect(notifications[0].title, 'Hello');
        expect(notifications[1].id, 'n2');
        expect(notifications[1].isOngoing, true);
        expect(bridge.lastBatchId, 'batch_123');
        expect(log.single.method, 'getNotifications');
      });

      test('supports legacy list response for backward compatibility', () async {
        mockHandler((call) async {
          return [
            {
              'id': 'n1',
              'packageName': 'com.test.app',
              'title': 'Legacy',
              'content': 'List',
              'timestamp': 1700000000000,
              'category': null,
              'isOngoing': false,
            },
          ];
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].id, 'n1');
        expect(notifications[0].title, 'Legacy');
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

      test('returns empty list on PlatformException (e.g. UNAUTHORIZED)', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'UNAUTHORIZED', message: 'Invalid session token');
        });
        final notifications = await bridge.getNotifications();
        expect(notifications, isEmpty);
      });
    });

    group('acknowledgeNotifications', () {
      test('sends token, notificationIds, and batchId to channel', () async {
        mockHandler((call) async {
          expect(call.arguments['token'], 'test-session-token');
          expect(call.arguments['notificationIds'], ['n1', 'n2']);
          expect(call.arguments['batchId'], 'batch_123');
          return true;
        });

        final success = await bridge.acknowledgeNotifications(
          ['n1', 'n2'],
          batchId: 'batch_123',
        );
        expect(success, true);
        expect(log.single.method, 'acknowledgeNotifications');
      });

      test('returns true without calling channel if notificationIds is empty', () async {
        mockHandler((call) async => true);
        final success = await bridge.acknowledgeNotifications([]);
        expect(success, true);
        expect(log, isEmpty);
      });

      test('returns false on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'UNAUTHORIZED', message: 'Invalid token');
        });
        final success = await bridge.acknowledgeNotifications(['n1']);
        expect(success, false);
      });
    });

    group('peekNotifications', () {
      test('returns notifications non-destructively', () async {
        mockHandler((call) async {
          expect(call.arguments['token'], 'test-session-token');
          return [
            {
              'id': 'p1',
              'packageName': 'com.peek.app',
              'title': 'Peek Title',
              'content': 'Peek Content',
              'timestamp': 1700000002000,
              'category': 'msg',
              'isOngoing': false,
            },
          ];
        });

        final notifications = await bridge.peekNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].id, 'p1');
        expect(log.single.method, 'peekNotifications');
      });

      test('returns empty list on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'Peek error');
        });
        final notifications = await bridge.peekNotifications();
        expect(notifications, isEmpty);
      });
    });

    group('getQueueSize', () {
      test('returns queue size from channel', () async {
        mockHandler((call) async {
          expect(call.arguments['token'], 'test-session-token');
          return 42;
        });

        final count = await bridge.getQueueSize();
        expect(count, 42);
        expect(log.single.method, 'getQueueSize');
      });

      test('returns 0 on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR');
        });
        final count = await bridge.getQueueSize();
        expect(count, 0);
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
        await bridge.openNotificationSettings();
      });
    });
  });
}
