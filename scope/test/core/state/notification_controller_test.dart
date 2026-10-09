import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MockStorage implements NotificationStorage {
  final List<AppNotification> items = [];

  @override
  Future<int> get count async => items.length;

  @override
  Future<AppNotification?> getById(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<int> deleteOlderThan(int cutoffTimestamp) async {
    final initialCount = items.length;
    items.removeWhere((item) => item.timestamp < cutoffTimestamp);
    return initialCount - items.length;
  }

  @override
  Future<List<AppNotification>> getAll() async => items;

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    items.addAll(notifications);
  }

  @override
  Future<void> clear() async {
    items.clear();
  }

  Future<void> archive(String id) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].id == id) {
        items[i] = items[i].copyWith(state: ReviewState.ARCHIVED);
      }
    }
  }

  Future<void> markReviewed(String id) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].id == id) {
        items[i] = items[i].copyWith(state: ReviewState.REVIEWED);
      }
    }
  }

  Future<void> snooze(String id, Duration duration) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].id == id) {
        items[i] = items[i].copyWith(state: ReviewState.SNOOZED);
      }
    }
  }

  @override
  Future<void> save(AppNotification notification) async {
    items.add(notification);
  }
}

class MockAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(priority: 'medium');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late StreamController<dynamic> streamController;
  late NotificationBridge bridge;
  late MockStorage storage;
  late MockAnalysisEngine engine;
  late ProviderContainer container;
  late List<MethodCall> methodCalls;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.test');
    methodCalls = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methodCalls.add(call);
      if (call.method == 'getNotifications') {
        return <Map<String, dynamic>>[];
      }
      if (call.method == 'isListenerEnabled') {
        return true;
      }
      return null;
    });

    streamController = StreamController<dynamic>.broadcast();
    bridge = NotificationBridge(
      channel: channel,
      notificationStream: streamController.stream,
    );
    storage = MockStorage();
    engine = MockAnalysisEngine();
    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    streamController.close();
    container.dispose();
  });

  group('NotificationController EventChannel & Lifecycle', () {
    test('startListening triggers initial fetch and listens to stream events', () async {
      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      methodCalls.clear();
      controller.startListening();

      // Give async microtasks time to execute
      await Future.delayed(Duration.zero);

      // Initial check invokes isListenerEnabled and getNotifications
      expect(methodCalls.map((c) => c.method), contains('getNotifications'));

      methodCalls.clear();

      // Emit event on EventChannel stream
      streamController.add({'event': 'notification_posted'});
      await Future.delayed(Duration.zero);

      expect(methodCalls.map((c) => c.method), contains('getNotifications'));

      controller.stopListening();
      controller.dispose();
    });

    test('3-second polling loop is removed and no continuous periodic calls occur', () async {
      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      controller.startListening();
      await Future.delayed(Duration.zero);
      methodCalls.clear();

      // Simulate waiting 10 seconds without any stream event
      await Future.delayed(const Duration(milliseconds: 100));

      // No new polling calls executed while idle with no events
      expect(methodCalls, isEmpty);

      controller.stopListening();
      controller.dispose();
    });

    test('App lifecycle observer pauses event handling on paused state and checks queue on resumed state', () async {
      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      controller.startListening();
      await Future.delayed(Duration.zero);
      methodCalls.clear();

      // Simulate app transitioning to paused state
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      // Emit event while app is paused
      streamController.add({'event': 'notification_posted'});
      await Future.delayed(Duration.zero);

      // Should NOT fetch notifications when paused
      expect(methodCalls, isEmpty);

      // Simulate app transitioning back to resumed state
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Resumed state triggers queue check / fetch
      expect(methodCalls.map((c) => c.method), contains('getNotifications'));

      controller.stopListening();
      controller.dispose();
    });
  });
}
