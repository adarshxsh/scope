import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/settings_screen.dart';

class FakeNotificationController extends NotificationController {
  bool clearAllCalled = false;
  bool generateTestDataCalled = false;

  @override
  Future<void> clearAll() async {
    clearAllCalled = true;
  }

  @override
  Future<void> generateTestData({bool? isReleaseMode}) async {
    if (isReleaseMode ?? false) {
      throw StateError('generateTestData is disabled in release builds.');
    }
    generateTestDataCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationController controller;

  setUp(() {
    controller = FakeNotificationController();
  });

  Widget buildApp({required bool isDebugOrProfileMode}) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsScreen(
          controller: controller,
          isDebugOrProfileMode: isDebugOrProfileMode,
        ),
      ),
    );
  }

  group('SettingsScreen Build Mode Tests', () {
    testWidgets('renders Developer section in debug/profile mode', (tester) async {
      await tester.pumpWidget(buildApp(isDebugOrProfileMode: true));
      await tester.pumpAndSettle();

      expect(find.text('Load Test Data', skipOffstage: false), findsOneWidget);
      expect(find.text('AI Playground (RLHF)', skipOffstage: false), findsOneWidget);
      expect(find.text('Diagnostics', skipOffstage: false), findsOneWidget);
    });

    testWidgets('omits Developer section in release mode', (tester) async {
      await tester.pumpWidget(buildApp(isDebugOrProfileMode: false));
      await tester.pumpAndSettle();

      expect(find.text('DEVELOPER'), findsNothing);
      expect(find.text('Load Test Data'), findsNothing);
      expect(find.text('AI Playground (RLHF)'), findsNothing);
      expect(find.text('Diagnostics'), findsNothing);

      // Verify user settings and Data Controls are still present
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);
      expect(find.text('DATA CONTROLS'), findsOneWidget);
      expect(find.text('Refresh Notifications'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);
    });

    testWidgets('Clear All Data shows explicit confirmation dialog before execution', (tester) async {
      await tester.pumpWidget(buildApp(isDebugOrProfileMode: false));
      await tester.pumpAndSettle();

      // Tap Clear All Data
      await tester.tap(find.text('Clear All Data'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog appears
      expect(find.text('Are you sure you want to clear all stored notifications? This action cannot be undone.'), findsOneWidget);

      // Tap Cancel first
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.clearAllCalled, isFalse);

      // Tap Clear All Data again
      await tester.tap(find.text('Clear All Data'));
      await tester.pumpAndSettle();

      // Tap Clear All in dialog
      await tester.tap(find.widgetWithText(TextButton, 'Clear All'));
      await tester.pumpAndSettle();

      expect(controller.clearAllCalled, isTrue);
    });
  });
}
