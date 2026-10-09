import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'medium',
      priorityScore: 0.50,
      classifiedCategory: 'msg',
    );
  }
}

class FailingNotificationStorage extends InMemoryNotificationStorage {
  bool shouldFail = false;

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    if (shouldFail) {
      throw Exception('Database write failed');
    }
    await super.saveAll(notifications);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late NotificationBridge bridge;
  late FailingNotificationStorage storage;
  late GhostAnalysisEngine engine;
  late List<MethodCall> channelCalls;

  setUp(() {
    channelCalls = [];
    channel = const MethodChannel('com.scope.notifications.ipc_test');
    bridge = NotificationBridge(channel: channel);
    storage = FailingNotificationStorage();
    engine = FakeGhostAnalysisEngine();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void setupChannelHandler({
    List<Map<String, dynamic>> peekResult = const [],
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      channelCalls.add(call);
      switch (call.method) {
        case 'isListenerEnabled':
          return true;
        case 'peekNotifications':
          return peekResult;
        case 'ackNotifications':
          return true;
        default:
          return null;
      }
    });
  }

  group('Two-Phase Peek and Acknowledge IPC Protocol', () {
    test('executes transactional peek-persist-acknowledge sequence in order', () async {
      final mockData = [
        {
          'id': 'n1',
          'packageName': 'com.test.app',
          'title': 'Peek Test 1',
          'content': 'Content 1',
          'timestamp': 1700000000000,
          'category': 'msg',
          'isOngoing': false,
        },
        {
          'id': 'n2',
          'packageName': 'com.test.app',
          'title': 'Peek Test 2',
          'content': 'Content 2',
          'timestamp': 1700000001000,
          'category': 'msg',
          'isOngoing': false,
        },
      ];

      setupChannelHandler(peekResult: mockData);

      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
      );

      await controller.fetchNotifications();

      // Verify channel call order: isListenerEnabled -> peekNotifications -> ackNotifications
      final methodNames = channelCalls.map((c) => c.method).toList();
      expect(methodNames, contains('peekNotifications'));
      expect(methodNames, contains('ackNotifications'));

      final peekIndex = methodNames.indexOf('peekNotifications');
      final ackIndex = methodNames.indexOf('ackNotifications');
      expect(peekIndex, lessThan(ackIndex));

      // Verify ack arguments match peeked IDs
      final ackCall = channelCalls.firstWhere((c) => c.method == 'ackNotifications');
      expect(ackCall.arguments, {'ids': ['n1', 'n2']});

      // Verify items were persisted to storage
      final stored = await storage.getAll();
      expect(stored.length, 2);
      expect(stored.map((n) => n.id), containsAll(['n1', 'n2']));

      controller.dispose();
    });

    test('does NOT acknowledge notifications if database persistence fails', () async {
      final mockData = [
        {
          'id': 'fail_n1',
          'packageName': 'com.test.app',
          'title': 'Fail Test',
          'content': 'Should not be acked',
          'timestamp': 1700000000000,
          'category': 'msg',
          'isOngoing': false,
        },
      ];

      setupChannelHandler(peekResult: mockData);
      storage.shouldFail = true; // Simulate database error

      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
      );

      await controller.fetchNotifications();

      final methodNames = channelCalls.map((c) => c.method).toList();
      expect(methodNames, contains('peekNotifications'));
      expect(methodNames, isNot(contains('ackNotifications')));

      controller.dispose();
    });

    test('handles concurrent fetch calls without dropping data or duplicate processing', () async {
      final mockData = [
        {
          'id': 'concurrent_1',
          'packageName': 'com.test.app',
          'title': 'Concurrent 1',
          'content': 'Content',
          'timestamp': 1700000000000,
          'category': 'msg',
          'isOngoing': false,
        },
      ];

      setupChannelHandler(peekResult: mockData);

      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
      );

      // Trigger concurrent fetches
      await Future.wait([
        controller.fetchNotifications(),
        controller.fetchNotifications(),
        controller.fetchNotifications(),
      ]);

      // Peek should be called, and ack should be called once due to lock
      final ackCalls = channelCalls.where((c) => c.method == 'ackNotifications').toList();
      expect(ackCalls.length, 1);

      controller.dispose();
    });
  });
}
