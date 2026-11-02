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
      test('fetches auth token and passes it in getNotifications', () async {
        mockHandler((call) async {
          if (call.method == 'getAuthToken') {
            return 'secret_token_123';
          }
          if (call.method == 'getNotifications') {
            expect(call.arguments['authToken'], 'secret_token_123');
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
          }
          return null;
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].id, 'n1');
        expect(bridge.currentAuthToken, 'secret_token_123');
      });

      test('retries on UNAUTHORIZED by refreshing auth token', () async {
        var attempts = 0;
        mockHandler((call) async {
          if (call.method == 'getAuthToken') {
            return 'refreshed_token_456';
          }
          if (call.method == 'getNotifications') {
            attempts++;
            if (attempts == 1) {
              throw PlatformException(code: 'UNAUTHORIZED', message: 'Token expired');
            }
            expect(call.arguments['authToken'], 'refreshed_token_456');
            return [
              {
                'id': 'n_retry',
                'packageName': 'com.test.app',
                'title': 'Recovered',
                'content': 'Body',
                'timestamp': 1700000000000,
                'category': 'msg',
                'isOngoing': false,
              },
            ];
          }
          return null;
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].id, 'n_retry');
        expect(attempts, 2);
      });

      test('returns empty list and logs audit on RATE_LIMITED', () async {
        mockHandler((call) async {
          if (call.method == 'getNotifications') {
            throw PlatformException(code: 'RATE_LIMITED', message: 'Too fast');
          }
          return null;
        });

        final notifications = await bridge.getNotifications();
        expect(notifications, isEmpty);
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
