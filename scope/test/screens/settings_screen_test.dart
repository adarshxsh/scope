import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  group('SettingsScreen Widget Tests', () {
    late AttentionDatabase db;
    late ProviderContainer container;
    late NotificationController controller;

    setUp(() async {
      db = AttentionDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      controller = NotificationController(container: container);
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      controller.dispose();
      container.dispose();
      await db.close();
    });

    testWidgets('SettingsScreen renders interactive tiles successfully', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      await tester.pump();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Event & Telemetry Logging'), findsOneWidget);
      expect(find.text('Telemetry Retention Period'), findsOneWidget);
      expect(find.text('Storage Quota Limit'), findsOneWidget);
      expect(find.text('Storage Quota Status'), findsOneWidget);
    });

    testWidgets('Toggling Event & Telemetry Logging updates database setting', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      await tester.pump();

      final switchFinder = find.byType(SwitchListTile);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pump();

      final settings = await db.userSettingsDao.getSettings();
      expect(settings.telemetryEnabled, isFalse);
    });

    testWidgets('Selecting Telemetry Retention Period opens picker and updates setting', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      await tester.pump();

      final tile = find.text('Telemetry Retention Period');
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Select Retention Period'), findsOneWidget);
      expect(find.text('14 Days'), findsOneWidget);

      await tester.tap(find.text('14 Days'));
      await tester.pump(const Duration(milliseconds: 200));

      final settings = await db.userSettingsDao.getSettings();
      expect(settings.retentionDays, equals(14));
    });

    testWidgets('Tapping Run Storage Cleanup executes cleanup and shows SnackBar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      await tester.pump();

      final cleanupTile = find.text('Run Storage Cleanup');
      await tester.tap(cleanupTile);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Storage quota cleanup executed'), findsOneWidget);
    });
  });
}
