import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FailingStorage extends InMemoryNotificationStorage {
  bool shouldFail = false;

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    if (shouldFail) {
      throw Exception('Database error on saveAll');
    }
    await super.saveAll(notifications);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> log;
  late FailingStorage failingStorage;
  late ProviderContainer container;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.test');
    log = [];
    failingStorage = FailingStorage();
    container = ProviderContainer();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'getNotifications') {
        return {
          'batchId': 'batch_fail_test',
          'notifications': [
            {
              'id': 'n_fail_1',
              'packageName': 'com.test.app',
              'title': 'Test Title',
              'content': 'Test Content',
              'timestamp': 1700000000000,
              'category': 'msg',
              'isOngoing': false,
            },
          ],
        };
      }
      if (call.method == 'acknowledgeNotifications') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  test('fetchNotifications skips acknowledgeNotifications on storage exception', () async {
    final bridge = NotificationBridge(channel: channel);
    final engine = GhostAnalysisEngine();
    await engine.initialize();

    final controller = NotificationController(
      bridge: bridge,
      storage: failingStorage,
      engine: engine,
      container: container,
    );

    // Cause storage saveAll to throw an exception
    failingStorage.shouldFail = true;

    await controller.fetchNotifications();

    final ackCalls = log.where((call) => call.method == 'acknowledgeNotifications');
    expect(ackCalls, isEmpty);
  });

  test('fetchNotifications calls acknowledgeNotifications after successful saveAll', () async {
    final bridge = NotificationBridge(channel: channel);
    final engine = GhostAnalysisEngine();
    await engine.initialize();

    final controller = NotificationController(
      bridge: bridge,
      storage: failingStorage,
      engine: engine,
      container: container,
    );

    failingStorage.shouldFail = false;

    await controller.fetchNotifications();

    final ackCalls = log.where((call) => call.method == 'acknowledgeNotifications');
    expect(ackCalls.length, 1);
    expect(ackCalls.first.arguments['notificationIds'], ['n_fail_1']);
    expect(ackCalls.first.arguments['batchId'], 'batch_fail_test');
  });
}
