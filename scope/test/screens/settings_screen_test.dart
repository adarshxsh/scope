import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/screens/settings_screen.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late NotificationController controller;
  late InMemoryNotificationStorage storage;
  late FakeGhostAnalysisEngine mockEngine;

  setUp(() {
    container = ProviderContainer();
    storage = InMemoryNotificationStorage();
    mockEngine = FakeGhostAnalysisEngine();
    controller = NotificationController(
      container: container,
      storage: storage,
      engine: mockEngine,
    );
  });

  tearDown(() {
    controller.dispose();
    container.dispose();
  });

  Widget buildApp() {
    return MaterialApp(
      home: Scaffold(
        body: SettingsScreen(controller: controller),
      ),
    );
  }

  group('SettingsScreen', () {
    testWidgets('renders consumer settings tiles in debug mode', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);
    });

    testWidgets('renders developer section and diagnostic tools in debug mode', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('DEVELOPER', skipOffstage: false), findsOneWidget);
      expect(find.text('Load Test Data', skipOffstage: false), findsOneWidget);
      expect(find.text('AI Playground (RLHF)', skipOffstage: false), findsOneWidget);
      expect(find.text('Diagnostics', skipOffstage: false), findsOneWidget);
      expect(find.text('Refresh Notifications', skipOffstage: false), findsOneWidget);
      expect(find.text('Clear All Data', skipOffstage: false), findsOneWidget);
    });
  });
}
