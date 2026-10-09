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
      test('fetches session token from channel', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') return 'valid-token-123';
          return null;
        });

        final token = await bridge.getSessionToken();
        expect(token, 'valid-token-123');
        expect(log.single.method, 'getSessionToken');
      });

      test('caches session token for subsequent calls', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') return 'valid-token-123';
          return null;
        });

        final token1 = await bridge.getSessionToken();
        final token2 = await bridge.getSessionToken();
        expect(token1, 'valid-token-123');
        expect(token2, 'valid-token-123');
        expect(log.length, 1); // Only invoked channel once
      });
    });

    group('getNotifications', () {
      test('returns parsed notifications from channel', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') return 'valid-token-123';
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
        expect(log.last.method, 'getNotifications');
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

      test('retries with new token when UNAUTHORIZED PlatformException is thrown', () async {
        int tokenFetchCount = 0;
        mockHandler((call) async {
          if (call.method == 'getSessionToken') {
            tokenFetchCount++;
            return 'token-$tokenFetchCount';
          }
          if (call.method == 'getNotifications') {
            final token = (call.arguments as Map?)?['token'];
            if (token == 'token-1') {
              throw PlatformException(code: 'UNAUTHORIZED', message: 'Token expired');
            }
            if (token == 'token-2') {
              return [
                {
                  'id': 'n1',
                  'packageName': 'com.test.app',
                  'title': 'Retried',
                  'content': 'Success',
                  'timestamp': 1700000000000,
                  'category': 'msg',
                  'isOngoing': false,
                }
              ];
            }
          }
          return null;
        });

        final notifications = await bridge.getNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].title, 'Retried');
        expect(tokenFetchCount, 2);
      });
    });

    group('two-phase pull protocol (peekNotifications and acknowledgeNotifications)', () {
      test('peekNotifications returns notification snapshot', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') return 'valid-token-123';
          if (call.method == 'peekNotifications') {
            final token = (call.arguments as Map?)?['token'];
            expect(token, 'valid-token-123');
            return [
              {
                'id': 'n1',
                'packageName': 'com.test.app',
                'title': 'Peeked Title',
                'content': 'Peeked Content',
                'timestamp': 1700000000000,
                'category': 'msg',
                'isOngoing': false,
              }
            ];
          }
          return null;
        });

        final notifications = await bridge.peekNotifications();
        expect(notifications.length, 1);
        expect(notifications[0].title, 'Peeked Title');
      });

      test('acknowledgeNotifications purges specified IDs', () async {
        mockHandler((call) async {
          if (call.method == 'getSessionToken') return 'valid-token-123';
          if (call.method == 'acknowledgeNotifications') {
            final args = call.arguments as Map?;
            expect(args?['token'], 'valid-token-123');
            expect(args?['ids'], ['n1', 'n2']);
            return ['n1', 'n2'];
          }
          return null;
        });

        final ackIds = await bridge.acknowledgeNotifications(['n1', 'n2']);
        expect(ackIds, ['n1', 'n2']);
      });

      test('acknowledgeNotifications returns empty list when given empty ids', () async {
        final ackIds = await bridge.acknowledgeNotifications([]);
        expect(ackIds, isEmpty);
        expect(log, isEmpty);
      });
    });

    group('getAuditMetrics', () {
      test('retrieves audit metrics from native channel', () async {
        mockHandler((call) async {
          if (call.method == 'getAuditMetrics') {
            return {
              'authorizedAccessCount': 5,
              'unauthorizedAccessCount': 0,
              'queueSize': 2,
            };
          }
          return null;
        });

        final metrics = await bridge.getAuditMetrics();
        expect(metrics['authorizedAccessCount'], 5);
        expect(metrics['unauthorizedAccessCount'], 0);
        expect(metrics['queueSize'], 2);
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
