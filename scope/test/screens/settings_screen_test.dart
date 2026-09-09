import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/preferences/user_preferences.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/settings_screen.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'medium',
      priorityScore: 0.50,
      classifiedCategory: 'msg',
      explanation: 'Test analysis',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationController controller;
  late InMemoryNotificationStorage storage;

  setUp(() {
    storage = InMemoryNotificationStorage();
    controller = NotificationController(
      bridge: NotificationBridge(),
      storage: storage,
      engine: FakeGhostAnalysisEngine(),
    );
  });

  Widget buildApp() {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SettingsScreen(controller: controller),
        ),
      ),
    );
  }

  group('SettingsScreen Widget Tests', () {
    testWidgets('renders data governance, retention, telemetry, and storage quota controls', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('DATA GOVERNANCE & STORAGE'), findsOneWidget);
      expect(find.text('Data Retention Duration'), findsOneWidget);
      expect(find.text('Telemetry & Behavioral Logging'), findsOneWidget);
      expect(find.text('Storage Quota Limit'), findsOneWidget);
      expect(find.text('Local Storage Consumed'), findsOneWidget);
      expect(find.text('PURGE NOW'), findsOneWidget);
    });

    testWidgets('toggling telemetry switch updates user preferences', (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, child) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                home: Scaffold(
                  body: SettingsScreen(controller: controller),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(userPreferencesProvider).telemetryEnabled, isTrue);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(userPreferencesProvider).telemetryEnabled, isFalse);
    });

    testWidgets('tapping PURGE NOW button triggers storage cleanup', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final purgeButton = find.text('PURGE NOW');
      expect(purgeButton, findsOneWidget);

      await tester.tap(purgeButton);
      await tester.pumpAndSettle();

      expect(find.text('Storage cleanup completed'), findsOneWidget);
    });
  });
}
