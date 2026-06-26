import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/notification_feed_screen.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {} // No-op, do not load assets in test

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    // Return mock prioritized notification immediately
    return notification.copyWith(
      priority: 'medium',
      priorityScore: 0.50,
      classifiedCategory: 'msg',
      explanation: 'Heuristic fallback in test',
      latencyMs: 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late NotificationBridge bridge;
  late InMemoryNotificationStorage storage;
  late GhostAnalysisEngine mockEngine;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.screentest');
    bridge = NotificationBridge(channel: channel);
    storage = InMemoryNotificationStorage();
    mockEngine = FakeGhostAnalysisEngine();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Helper to set up mock responses for the channel.
  void setupMock({
    bool isListenerEnabled = true,
    List<Map<String, dynamic>> notifications = const [],
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isListenerEnabled':
          return isListenerEnabled;
        case 'getNotifications':
          return notifications;
        case 'openNotificationSettings':
          return true;
        default:
          return null;
      }
    });
  }

  Widget buildApp({
    NotificationBridge? overrideBridge,
    InMemoryNotificationStorage? overrideStorage,
    GhostAnalysisEngine? overrideEngine,
  }) {
    return MaterialApp(
      home: NotificationFeedScreen(
        bridge: overrideBridge ?? bridge,
        storage: overrideStorage ?? storage,
        engine: overrideEngine ?? mockEngine,
      ),
    );
  }

  group('NotificationFeedScreen', () {
    testWidgets('shows empty state when no notifications', (tester) async {
      setupMock(isListenerEnabled: true, notifications: []);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No notifications captured yet'), findsOneWidget);
      expect(find.text('AttentionOS'), findsOneWidget);
    });

    testWidgets('shows permission banner when listener is disabled',
        (tester) async {
      setupMock(isListenerEnabled: false, notifications: []);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('OPEN SETTINGS'), findsOneWidget);
      expect(find.text('RE-CHECK'), findsOneWidget);
      expect(
        find.textContaining('Notification access is not enabled'),
        findsOneWidget,
      );
    });

    testWidgets('hides permission banner when listener is enabled',
        (tester) async {
      setupMock(isListenerEnabled: true, notifications: []);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('OPEN SETTINGS'), findsNothing);
    });

    testWidgets('displays notification cards from bridge', (tester) async {
      setupMock(
        isListenerEnabled: true,
        notifications: [
          {
            'id': 'n1',
            'packageName': 'com.test.app',
            'title': 'Test Notification',
            'content': 'This is a test',
            'timestamp': DateTime(2024, 1, 15, 14, 30).millisecondsSinceEpoch,
            'category': 'msg',
            'isOngoing': false,
          },
        ],
      );
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Test Notification'), findsOneWidget);
      expect(find.text('This is a test'), findsOneWidget);
      expect(find.textContaining('com.test.app'), findsOneWidget);
    });

    testWidgets('shows notification count header', (tester) async {
      setupMock(
        isListenerEnabled: true,
        notifications: [
          {
            'id': 'n1',
            'packageName': 'com.test',
            'title': 'Title',
            'content': 'Content',
            'timestamp': 1700000000000,
            'category': null,
            'isOngoing': false,
          },
        ],
      );
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('1 notification(s) captured'), findsOneWidget);
      expect(find.text('CLEAR ALL'), findsOneWidget);
    });

    testWidgets('clear all button removes notifications', (tester) async {
      setupMock(
        isListenerEnabled: true,
        notifications: [
          {
            'id': 'n1',
            'packageName': 'com.test',
            'title': 'Title',
            'content': 'Content',
            'timestamp': 1700000000000,
            'category': null,
            'isOngoing': false,
          },
        ],
      );
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Verify notification is shown
      expect(find.text('Title'), findsOneWidget);

      // Now clear — but first we need to re-mock to return empty
      // (since the bridge will be polled again)
      setupMock(isListenerEnabled: true, notifications: []);

      await tester.tap(find.text('CLEAR ALL'));
      await tester.pumpAndSettle();

      expect(find.text('No notifications captured yet'), findsOneWidget);
    });
  });
}
