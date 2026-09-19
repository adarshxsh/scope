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
    group('getSessionToken', () {
      test('fetches session token from channel and caches it', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') {
            return 'test-session-token-123';
          }
          return null;
        });

        final token1 = await bridge.getSessionToken();
        expect(token1, 'test-session-token-123');

        // Second call should return cached token without making another channel call
        final token2 = await bridge.getSessionToken();
        expect(token2, 'test-session-token-123');
        expect(log.length, 1);
        expect(log.single.method, 'getSessionToken');
      });

      test('returns null on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'token error');
        });

        final token = await bridge.getSessionToken();
        expect(token, isNull);
      });
    });

    group('peekNotifications', () {
      test('returns parsed notifications from channel via peekNotifications method', () async {
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

        final notifications = await bridge.peekNotifications();
        expect(notifications.length, 2);
        expect(notifications[0].id, 'n1');
        expect(notifications[0].title, 'Hello');
        expect(notifications[1].id, 'n2');
        expect(notifications[1].isOngoing, true);
        expect(log.single.method, 'peekNotifications');
      });

      test('returns empty list when channel returns null', () async {
        mockHandler((call) async => null);
        final notifications = await bridge.peekNotifications();
        expect(notifications, isEmpty);
      });

      test('returns empty list on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'test error');
        });
        final notifications = await bridge.peekNotifications();
        expect(notifications, isEmpty);
      });
    });

    group('acknowledgeNotifications', () {
      test('sends session token and notification IDs to channel', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') {
            return 'valid-token-xyz';
          } else if (call.method == 'acknowledgeNotifications') {
            final args = call.arguments as Map;
            expect(args['token'], 'valid-token-xyz');
            expect(args['ids'], ['n1', 'n2']);
            return true;
          }
          return null;
        });

        final result = await bridge.acknowledgeNotifications(['n1', 'n2']);
        expect(result, isTrue);
        expect(log.map((c) => c.method).toList(), ['getSessionToken', 'acknowledgeNotifications']);
      });

      test('returns true for empty IDs without making channel call', () async {
        mockHandler((call) async => true);
        final result = await bridge.acknowledgeNotifications([]);
        expect(result, isTrue);
        expect(log, isEmpty);
      });

      test('returns false when channel throws authorization exception', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') {
            return 'invalid-token';
          } else if (call.method == 'acknowledgeNotifications') {
            throw PlatformException(code: 'UNAUTHORIZED', message: 'Invalid session token');
          }
          return null;
        });

        final result = await bridge.acknowledgeNotifications(['n1']);
        expect(result, isFalse);
      });
    });

    group('getNotifications', () {
      test('delegates to peekNotifications', () async {
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
          ];
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 1);
        expect(log.single.method, 'peekNotifications');
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
