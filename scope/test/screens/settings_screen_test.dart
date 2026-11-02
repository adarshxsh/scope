import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Widget buildTestableWidget(Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('SettingsScreen Widget Tests', () {
    testWidgets('renders retention duration dropdown and telemetry collection switch', (tester) async {
      await tester.pumpWidget(buildTestableWidget(SettingsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Retention Duration'), findsOneWidget);
      expect(find.text('7 Days retention window'), findsOneWidget);
      expect(find.text('Telemetry Collection'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('toggling telemetry switch updates controller state immediately', (tester) async {
      await tester.pumpWidget(buildTestableWidget(SettingsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(controller.telemetryEnabled, isTrue);

      final switchFinder = find.byKey(const Key('telemetry_switch'));
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(controller.telemetryEnabled, isFalse);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('changing retention dropdown updates controller retentionDays immediately', (tester) async {
      await tester.pumpWidget(buildTestableWidget(SettingsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(controller.retentionDays, equals(7));

      final dropdownFinder = find.byKey(const Key('retention_dropdown'));
      expect(dropdownFinder, findsOneWidget);

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      final menuItemFinder = find.text('14 Days').last;
      await tester.tap(menuItemFinder);
      await tester.pumpAndSettle();

      expect(controller.retentionDays, equals(14));
      expect(find.text('14 Days retention window'), findsOneWidget);
    });
  });
}
