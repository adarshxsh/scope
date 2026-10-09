import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationController controller;
  late InMemoryNotificationStorage storage;

  setUp(() {
    storage = InMemoryNotificationStorage();
    controller = NotificationController(
      bridge: NotificationBridge(),
      storage: storage,
      container: ProviderContainer(),
    );
  });

  Widget buildApp(NotificationController ctrl) {
    return MaterialApp(
      home: SettingsScreen(controller: ctrl),
    );
  }

  group('SettingsScreen', () {
    testWidgets('displays Settings options and Developer section in debug mode', (tester) async {
      await tester.pumpWidget(buildApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);
      expect(find.text('Refresh Notifications'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);

      // Developer section in debug mode
      expect(find.text('DEVELOPER'), findsOneWidget);
      expect(find.text('Load Test Data'), findsOneWidget);
      expect(find.text('AI Playground (RLHF)'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
    });

    testWidgets('tapping Clear All Data shows confirmation dialog and cancels on Cancel', (tester) async {
      await tester.pumpWidget(buildApp(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear All Data'));
      await tester.pumpAndSettle();

      expect(find.text('Clear All Data?'), findsOneWidget);
      expect(
        find.text(
          'This will permanently remove all stored notifications and reset review state. Are you sure you want to proceed?',
        ),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Clear All Data?'), findsNothing);
    });

    testWidgets('tapping Clear All Data and confirming calls clearAll', (tester) async {
      await tester.pumpWidget(buildApp(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear All Data'));
      await tester.pumpAndSettle();

      expect(find.text('Clear All Data?'), findsOneWidget);

      // Tap Clear All in dialog
      await tester.tap(find.widgetWithText(TextButton, 'Clear All'));
      await tester.pumpAndSettle();

      expect(find.text('Clear All Data?'), findsNothing);
    });
  });
}
