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
    group('fetchPendingNotifications', () {
      test('returns parsed NotificationBatch from channel', () async {
        mockHandler((call) async {
          if (call.method == 'fetchPendingNotifications') {
            return {
              'batchId': 'tx_123',
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
              ],
            };
          }
          return null;
        });

        final batch = await bridge.fetchPendingNotifications();
        expect(batch, isNotNull);
        expect(batch!.batchId, 'tx_123');
        expect(batch.notifications.length, 1);
        expect(batch.notifications[0].title, 'Hello');
        expect(log.single.method, 'fetchPendingNotifications');
      });

      test('returns null when channel returns null', () async {
        mockHandler((call) async => null);
        final batch = await bridge.fetchPendingNotifications();
        expect(batch, isNull);
      });
    });

    group('acknowledgeNotifications', () {
      test('invokes acknowledgeNotifications with batchId and returns true', () async {
        mockHandler((call) async {
          if (call.method == 'acknowledgeNotifications') {
            expect(call.arguments['batchId'], 'tx_123');
            return true;
          }
          return false;
        });

        final result = await bridge.acknowledgeNotifications('tx_123');
        expect(result, isTrue);
        expect(log.single.method, 'acknowledgeNotifications');
      });
    });

    group('peekNotificationCount', () {
      test('invokes peekNotificationCount and returns queue size', () async {
        mockHandler((call) async {
          if (call.method == 'peekNotificationCount') {
            return 5;
          }
          return 0;
        });

        final count = await bridge.peekNotificationCount();
        expect(count, 5);
        expect(log.single.method, 'peekNotificationCount');
      });
    });

    group('fetchAndAcknowledge', () {
      test('acknowledges batch only after onSave callback completes successfully', () async {
        bool saveExecuted = false;

        mockHandler((call) async {
          if (call.method == 'fetchPendingNotifications') {
            return {
              'batchId': 'tx_999',
              'notifications': [
                {
                  'id': 'n1',
                  'packageName': 'com.test.app',
                  'title': 'Test',
                  'content': 'Body',
                  'timestamp': 1700000000000,
                  'category': 'msg',
                  'isOngoing': false,
                },
              ],
            };
          }
          if (call.method == 'acknowledgeNotifications') {
            expect(saveExecuted, isTrue);
            return true;
          }
          return null;
        });

        final result = await bridge.fetchAndAcknowledge(
          onSave: (notifs) async {
            expect(notifs.length, 1);
            saveExecuted = true;
          },
        );

        expect(result.length, 1);
        expect(saveExecuted, isTrue);
        expect(log.map((c) => c.method).toList(), [
          'fetchPendingNotifications',
          'acknowledgeNotifications',
        ]);
      });

      test('does NOT acknowledge batch if onSave callback throws an exception', () async {
        mockHandler((call) async {
          if (call.method == 'fetchPendingNotifications') {
            return {
              'batchId': 'tx_error',
              'notifications': [
                {
                  'id': 'n1',
                  'packageName': 'com.test.app',
                  'title': 'Error Test',
                  'content': 'Body',
                  'timestamp': 1700000000000,
                  'category': 'msg',
                  'isOngoing': false,
                },
              ],
            };
          }
          return null;
        });

        expect(
          () async => await bridge.fetchAndAcknowledge(
            onSave: (notifs) async {
              throw Exception('Database persistence error');
            },
          ),
          throwsA(isA<Exception>()),
        );

        // Check that acknowledgeNotifications was NEVER called
        expect(log.map((c) => c.method).toList(), ['fetchPendingNotifications']);
      });
    });

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
        expect(log.map((c) => c.method), contains('getNotifications'));
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
