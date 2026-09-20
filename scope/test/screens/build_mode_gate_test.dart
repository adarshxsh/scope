import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/notification_feed_screen.dart';
import 'package:scope/screens/settings_screen.dart';

class FakeEngine extends GhostAnalysisEngine {
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
  late NotificationBridge bridge;
  late InMemoryNotificationStorage storage;
  late FakeEngine engine;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.gatetest');
    bridge = NotificationBridge(channel: channel);
    storage = InMemoryNotificationStorage();
    engine = FakeEngine();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isListenerEnabled':
          return true;
        case 'getNotifications':
          return <Map<String, dynamic>>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Build Mode Gating Tests', () {
    testWidgets('SettingsScreen hides Developer section in release mode and shows in debug mode', (tester) async {
      final container = ProviderContainer();
      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SettingsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Standard end-user settings tile must always be visible
      expect(find.text('Refresh Notifications'), findsOneWidget);

      if (kReleaseMode) {
        expect(find.text('DEVELOPER'), findsNothing);
        expect(find.text('Load Test Data'), findsNothing);
        expect(find.text('AI Playground (RLHF)'), findsNothing);
        expect(find.text('Diagnostics'), findsNothing);
        expect(find.text('Clear All Data'), findsNothing);
      } else {
        expect(find.text('DEVELOPER'), findsOneWidget);
        expect(find.text('Load Test Data'), findsOneWidget);
        expect(find.text('AI Playground (RLHF)'), findsOneWidget);
        expect(find.text('Diagnostics'), findsOneWidget);
        expect(find.text('Clear All Data'), findsOneWidget);
      }

      controller.dispose();
      container.dispose();
    });

    testWidgets('NotificationFeedScreen hides Diagnostics, TEST, and CLEAR ALL buttons in release mode', (tester) async {
      // Seed storage with a notification so CLEAR ALL would be rendered if allowed
      await storage.saveAll([
        const AppNotification(
          id: '1',
          packageName: 'com.example',
          title: 'Hello',
          content: 'World',
          timestamp: 1000000,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationFeedScreen(
            bridge: bridge,
            storage: storage,
            engine: engine,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (kReleaseMode) {
        expect(find.byIcon(Icons.analytics), findsNothing);
        expect(find.text('TEST'), findsNothing);
        expect(find.text('CLEAR ALL'), findsNothing);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      } else {
        expect(find.byIcon(Icons.analytics), findsOneWidget);
        expect(find.text('TEST'), findsOneWidget);
        expect(find.text('CLEAR ALL'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      }
    });

    test('NotificationController guards generateTestData and clearAll in release mode', () async {
      final container = ProviderContainer();
      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      // Seed storage
      await storage.saveAll([
        const AppNotification(
          id: 'test_1',
          packageName: 'com.test',
          title: 'Test',
          content: 'Test content',
          timestamp: 12345,
        ),
      ]);

      if (kReleaseMode) {
        await controller.generateTestData();
        final afterGen = await storage.getAll();
        // Storage should still only have 1 item (test generation rejected)
        expect(afterGen.length, equals(1));

        await controller.clearAll();
        final afterClear = await storage.getAll();
        // Storage should still have 1 item (clear rejected)
        expect(afterClear.length, equals(1));
      } else {
        await controller.generateTestData();
        final afterGen = await storage.getAll();
        // Test data generated
        expect(afterGen.length, greaterThan(1));

        await controller.clearAll();
        final afterClear = await storage.getAll();
        // Cleared
        expect(afterClear.isEmpty, isTrue);
      }

      controller.dispose();
      container.dispose();
    });
  });
}
