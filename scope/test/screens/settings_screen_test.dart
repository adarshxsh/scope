import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationController controller;

  setUp(() {
    controller = NotificationController(isReleaseMode: false);
  });

  tearDown(() {
    controller.dispose();
  });

  group('SettingsScreen Build Mode Guard Tests', () {
    testWidgets('Renders Developer section and all tiles in debug mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            controller: controller,
            isReleaseMode: false,
          ),
        ),
      );

      // Section header
      expect(find.text('DEVELOPER'), findsOneWidget);

      // Developer tiles
      expect(find.text('Load Test Data'), findsOneWidget);
      expect(find.text('AI Playground (RLHF)'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.text('Refresh Notifications'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);

      // Production tiles
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);
    });

    testWidgets('Completely hides Developer section and tiles in release mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            controller: controller,
            isReleaseMode: true,
          ),
        ),
      );

      // Section header
      expect(find.text('DEVELOPER'), findsNothing);

      // Developer tiles
      expect(find.text('Load Test Data'), findsNothing);
      expect(find.text('AI Playground (RLHF)'), findsNothing);
      expect(find.text('Diagnostics'), findsNothing);
      expect(find.text('Clear All Data'), findsNothing);

      // Production tiles must still render
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);
    });
  });
}
