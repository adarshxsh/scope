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
      test('returns NotificationBatch with batchId and notifications when channel returns Map', () async {
        mockHandler((call) async {
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
            ]
          };
        });

        final batch = await bridge.getNotifications();
        expect(batch.batchId, 'batch_123');
        expect(batch.notifications.length, 2);
        expect(batch.notifications[0].id, 'n1');
        expect(batch.notifications[0].title, 'Hello');
        expect(batch.notifications[1].id, 'n2');
        expect(batch.notifications[1].isOngoing, true);
        expect(log.single.method, 'getNotifications');
      });

      test('returns NotificationBatch with empty batchId when channel returns List (backward compatibility)', () async {
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

        final batch = await bridge.getNotifications();
        expect(batch.batchId, isEmpty);
        expect(batch.notifications.length, 1);
        expect(batch.notifications[0].id, 'n1');
      });

      test('returns empty NotificationBatch when channel returns null', () async {
        mockHandler((call) async => null);
        final batch = await bridge.getNotifications();
        expect(batch.batchId, isEmpty);
        expect(batch.notifications, isEmpty);
      });

      test('returns empty NotificationBatch when channel returns empty map/list', () async {
        mockHandler((call) async => <String, dynamic>{'batchId': '', 'notifications': []});
        final batch = await bridge.getNotifications();
        expect(batch.batchId, isEmpty);
        expect(batch.notifications, isEmpty);
      });

      test('returns empty NotificationBatch on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR', message: 'test error');
        });
        final batch = await bridge.getNotifications();
        expect(batch.batchId, isEmpty);
        expect(batch.notifications, isEmpty);
      });
    });

    group('acknowledgeNotifications', () {
      test('invokes acknowledgeNotifications method on channel with batchId', () async {
        mockHandler((call) async {
          if (call.method == 'acknowledgeNotifications') {
            final args = call.arguments as Map;
            return args['batchId'] == 'batch_123';
          }
          return false;
        });

        final result = await bridge.acknowledgeNotifications('batch_123');
        expect(result, isTrue);
        expect(log.single.method, 'acknowledgeNotifications');
        expect((log.single.arguments as Map)['batchId'], 'batch_123');
      });

      test('returns false without calling channel when batchId is empty', () async {
        mockHandler((call) async => true);
        final result = await bridge.acknowledgeNotifications('');
        expect(result, isFalse);
        expect(log, isEmpty);
      });
    });

    group('peekQueue and getQueueSize', () {
      test('peekQueue returns non-destructive list of notifications', () async {
        mockHandler((call) async {
          return [
            {
              'id': 'n1',
              'packageName': 'com.test.app',
              'title': 'Peek Title',
              'content': 'Peek Content',
              'timestamp': 1700000000000,
              'category': 'msg',
              'isOngoing': false,
            }
          ];
        });

        final items = await bridge.peekQueue();
        expect(items.length, 1);
        expect(items[0].title, 'Peek Title');
        expect(log.single.method, 'peekQueue');
      });

      test('getQueueSize returns queue count', () async {
        mockHandler((call) async => 5);
        final size = await bridge.getQueueSize();
        expect(size, 5);
        expect(log.single.method, 'getQueueSize');
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
