import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/settings_screen.dart';

class MockNotificationBridge extends NotificationBridge {
  @override
  Future<bool> isListenerEnabled() async => true;

  @override
  Future<List<AppNotification>> getNotifications() async => [];
}

void main() {
  group('SettingsScreen Widget Tests', () {
    late NotificationController controller;

    setUp(() {
      controller = NotificationController(
        bridge: MockNotificationBridge(),
        storage: InMemoryNotificationStorage(),
        container: ProviderContainer(),
      );
    });

    testWidgets('SettingsScreen renders standard settings and developer section in debug mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(controller: controller),
          ),
        ),
      );

      // Verify standard settings
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notification Access'), findsOneWidget);

      // In debug mode, Developer section is present
      if (kDebugMode) {
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();

        expect(find.text('DEVELOPER'), findsOneWidget);
        expect(find.text('Load Test Data'), findsOneWidget);
        expect(find.text('AI Playground (RLHF)'), findsOneWidget);
        expect(find.text('Diagnostics'), findsOneWidget);
        expect(find.text('Refresh Notifications'), findsOneWidget);
        expect(find.text('Clear All Data'), findsOneWidget);
      }
    });
  });
}
