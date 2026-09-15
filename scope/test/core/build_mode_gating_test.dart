import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/ai_playground_screen.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/screens/notification_feed_screen.dart';
import 'package:scope/screens/settings_screen.dart';
import 'package:scope/theme/scope_navigator.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationController controller;
  late GhostAnalysisEngine mockEngine;

  setUp(() {
    mockEngine = FakeGhostAnalysisEngine();
    controller = NotificationController(
      bridge: NotificationBridge(),
      storage: InMemoryNotificationStorage(),
      engine: mockEngine,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('Build Mode Gating Tests', () {
    test('NotificationController diagnostic actions are available in debug mode', () async {
      expect(kDebugMode, isTrue);

      // Should execute without throwing UnsupportedError in debug mode
      await controller.generateTestData();
      expect(controller.notifications, isNotEmpty);

      await controller.clearAll();
      expect(controller.notifications, isEmpty);
    });

    testWidgets('SettingsScreen shows Developer section in debug mode', (tester) async {
      expect(kDebugMode, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DEVELOPER'), findsOneWidget);
      expect(find.text('Load Test Data'), findsOneWidget);
      expect(find.text('AI Playground (RLHF)'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);
      expect(find.text('Refresh Notifications'), findsOneWidget);
    });

    testWidgets('NotificationFeedScreen shows Diagnostics icon and TEST button in debug mode',
        (tester) async {
      expect(kDebugMode, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationFeedScreen(
            bridge: NotificationBridge(),
            storage: InMemoryNotificationStorage(),
            engine: mockEngine,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.analytics), findsOneWidget);
      expect(find.text('TEST'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('DiagnosticScreen and AiPlaygroundScreen instantiate and build in debug mode',
        (tester) async {
      expect(kDebugMode, isTrue);

      // DiagnosticScreen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticScreen(engine: mockEngine),
          ),
        ),
      );
      expect(find.text('Ghost AI Diagnostics'), findsOneWidget);

      // AiPlaygroundScreen
      await tester.pumpWidget(
        MaterialApp(
          home: AiPlaygroundScreen(controller: controller),
        ),
      );
      expect(find.text('AI Playground (RLHF)'), findsOneWidget);
    });

    testWidgets('ScopeNavigator pushes developer screens successfully in debug mode',
        (tester) async {
      expect(kDebugMode, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  ScopeNavigator.push(
                    context,
                    DiagnosticScreen(engine: mockEngine),
                  );
                },
                child: const Text('Open Diagnostics'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('Ghost AI Diagnostics'), findsOneWidget);
    });
  });
}
