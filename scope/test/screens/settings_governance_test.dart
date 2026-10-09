import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  late ProviderContainer container;
  late NotificationController controller;

  setUp(() {
    container = ProviderContainer();
    controller = NotificationController(container: container);
  });

  tearDown(() {
    controller.dispose();
    container.dispose();
  });

  group('NotificationController Governance Tests', () {
    test('default governance settings values', () {
      expect(controller.retentionDays, equals(7));
      expect(controller.telemetryLoggingEnabled, isTrue);
      expect(controller.storageQuotaCap, equals(1000));
    });

    test('updating retention days notifies listeners', () async {
      int notified = 0;
      controller.addListener(() => notified++);

      await controller.setRetentionDays(14);
      expect(controller.retentionDays, equals(14));
      expect(notified, greaterThanOrEqualTo(1));
    });

    test('updating telemetry logging notifies listeners', () async {
      int notified = 0;
      controller.addListener(() => notified++);

      await controller.setTelemetryLoggingEnabled(false);
      expect(controller.telemetryLoggingEnabled, isFalse);
      expect(notified, equals(1));
    });

    test('updating storage quota cap notifies listeners', () async {
      int notified = 0;
      controller.addListener(() => notified++);

      await controller.setStorageQuotaCap(500);
      expect(controller.storageQuotaCap, equals(500));
      expect(notified, greaterThanOrEqualTo(1));
    });
  });

  group('SettingsScreen Governance UI Tests', () {
    testWidgets('renders retention, telemetry, and storage quota controls', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SettingsScreen(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retention Period'), findsOneWidget);
      expect(find.text('Telemetry Event Logging'), findsOneWidget);
      expect(find.text('Storage Quota Cap'), findsOneWidget);
      expect(find.text('PRIVACY & GOVERNANCE'), findsOneWidget);
    });
  });
}

