import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/settings_screen.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MockNotificationController extends NotificationController {
  bool clearAllCalled = false;
  bool generateTestDataCalled = false;

  MockNotificationController()
      : super(
          bridge: NotificationBridge(),
          storage: InMemoryNotificationStorage(),
          engine: GhostAnalysisEngine(),
          container: ProviderContainer(),
        );

  @override
  Future<void> clearAll() async {
    clearAllCalled = true;
  }

  @override
  Future<void> generateTestData() async {
    generateTestDataCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNotificationController controller;

  setUp(() {
    controller = MockNotificationController();
  });

  Widget buildApp(NotificationController controller) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsScreen(controller: controller),
      ),
    );
  }

  group('SettingsScreen Widget Tests', () {
    testWidgets('renders standard settings and developer tiles in debug mode', (tester) async {
      await tester.pumpWidget(buildApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);
      expect(find.text('Refresh Notifications'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);

      // In debug mode (default in test), developer section should be present
      expect(find.text('DEVELOPER'), findsOneWidget);
      expect(find.text('Load Test Data'), findsOneWidget);
      expect(find.text('AI Playground (RLHF)'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
    });

    testWidgets('Clear All Data shows confirmation dialog and cancels without clearing', (tester) async {
      await tester.pumpWidget(buildApp(controller));
      await tester.pumpAndSettle();

      // Tap Clear All Data tile
      await tester.tap(find.text('Clear All Data'));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Clear All Data?'), findsOneWidget);
      expect(
        find.text('Are you sure you want to remove all stored notifications? This action cannot be undone.'),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should disappear, clearAll should not be called
      expect(find.text('Clear All Data?'), findsNothing);
      expect(controller.clearAllCalled, isFalse);
    });

    testWidgets('Clear All Data shows confirmation dialog and clears data when confirmed', (tester) async {
      await tester.pumpWidget(buildApp(controller));
      await tester.pumpAndSettle();

      // Tap Clear All Data tile
      await tester.tap(find.text('Clear All Data'));
      await tester.pumpAndSettle();

      // Tap Clear All in dialog
      await tester.tap(find.text('Clear All').last);
      await tester.pumpAndSettle();

      // Dialog should disappear, clearAll should be called
      expect(find.text('Clear All Data?'), findsNothing);
      expect(controller.clearAllCalled, isTrue);
    });
  });
}
