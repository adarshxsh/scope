import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen renders storage governance and telemetry controls', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = NotificationController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(controller: controller),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify sections header
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('STORAGE & RETENTION GOVERNANCE'), findsOneWidget);

    // Verify Telemetry switch tile
    expect(find.text('Telemetry Logging'), findsOneWidget);
    expect(find.byKey(const Key('telemetry_switch')), findsOneWidget);

    // Verify Live Storage Statistics card
    expect(find.text('Live Storage Statistics'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Est. DB Size'), findsOneWidget);

    // Verify Retention Window dropdown
    await tester.ensureVisible(find.byKey(const Key('retention_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Retention Window'), findsOneWidget);
    expect(find.byKey(const Key('retention_dropdown')), findsOneWidget);

    // Verify Storage Quota Limit dropdown
    expect(find.text('Storage Quota Limit'), findsOneWidget);
    expect(find.byKey(const Key('quota_dropdown')), findsOneWidget);

    // Verify Purge Expired Data Now tile
    expect(find.text('Purge Expired Data Now'), findsOneWidget);

    // Tap purge tile and verify SnackBar
    await tester.tap(find.byKey(const Key('purge_data_tile')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Storage cleanup complete'), findsOneWidget);

    // Toggle telemetry switch
    await tester.ensureVisible(find.byKey(const Key('telemetry_switch')));
    await tester.tap(find.byKey(const Key('telemetry_switch')));
    await tester.pumpAndSettle();
    expect(controller.telemetryEnabled, isFalse);

    controller.dispose();
  });
}


