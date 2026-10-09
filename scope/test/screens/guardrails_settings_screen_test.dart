import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/guardrails_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/screens/guardrails_settings_screen.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'medium',
      priorityScore: 0.50,
      classifiedCategory: 'msg',
      explanation: 'Heuristic fallback in test',
      latencyMs: 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late GuardrailService guardrails;
  late NotificationStorage storage;
  late NotificationController controller;

  setUp(() async {
    db = AttentionDatabase.inMemory();
    guardrails = GuardrailService(db);
    storage = InMemoryNotificationStorage();
    controller = NotificationController(
      storage: storage,
      guardrails: guardrails,
      engine: FakeGhostAnalysisEngine(),
    );
    await Future.delayed(const Duration(milliseconds: 10));
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Widget buildTestableWidget() {
    return MaterialApp(
      home: GuardrailsSettingsScreen(controller: controller),
    );
  }

  group('GuardrailsSettingsScreen Widget Tests', () {
    testWidgets('Renders Sensitive Category Guardrails and App Exclusion list', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      expect(find.text('Notification Guardrails'), findsWidgets);
      expect(find.text('SENSITIVE CATEGORY GUARDRAILS'), findsOneWidget);
      expect(find.text('PER-APP EXCLUSION SETTINGS'), findsOneWidget);

      expect(find.text('Banking & OTP'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('Messaging'), findsOneWidget);
    });

    testWidgets('Toggling category switch mutes category and displays MUTED badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      expect(find.text('MUTED'), findsNothing);

      // Find switch for Banking & OTP (first switch in list)
      final switches = find.byType(Switch);
      expect(switches, findsAtLeastNWidgets(3));

      await tester.tap(switches.first);
      await tester.pumpAndSettle();

      expect(controller.guardrails.isCategoryMuted(SensitiveCategory.bankingOtp), isTrue);
      expect(find.text('MUTED'), findsAtLeastNWidgets(1));
    });

    testWidgets('Search bar filters app exclusion list', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'whatsapp');
      await tester.pumpAndSettle();

      expect(find.text('Whatsapp'), findsOneWidget);
      expect(find.text('com.whatsapp'), findsOneWidget);
    });

    testWidgets('Toggling app switch excludes app package', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'slack');
      await tester.pumpAndSettle();

      expect(find.text('Slack'), findsOneWidget);

      final appSwitch = find.byType(Switch).last;
      await tester.tap(appSwitch);
      await tester.pumpAndSettle();

      expect(controller.guardrails.isPackageExcluded('com.slack'), isTrue);
      expect(find.text('EXCLUDED'), findsOneWidget);
    });
  });
}
