import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/ai_playground_screen.dart';

class FakePlaygroundEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'high',
      priorityScore: 0.85,
      classifiedCategory: 'financial',
      explanation: 'Debit alert with OTP and amount',
      latencyMs: 5,
      extractedFeatures: const {
        'otp': '987652',
        'amount': 500,
        'hasDeadline': false,
      },
    );
  }
}

void main() {
  group('AiPlaygroundScreen Privacy Tests', () {
    late InMemoryNotificationStorage storage;
    late FakePlaygroundEngine mockEngine;
    late NotificationController controller;

    setUp(() {
      storage = InMemoryNotificationStorage();
      mockEngine = FakePlaygroundEngine();
      controller = NotificationController(storage: storage, engine: mockEngine);
    });

    testWidgets('Simulator mode runs analysis and redacts defining feature chips by default',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiPlaygroundScreen(controller: controller),
        ),
      );

      expect(find.text('AI Playground (RLHF)'), findsOneWidget);

      // Switch to Simulator Mode
      await tester.tap(find.text('Simulator Mode'));
      await tester.pumpAndSettle();

      // Enter custom input
      final titleField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText?.contains('Title') == true,
      );
      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText?.contains('Content') == true,
      );

      await tester.enterText(titleField, 'Bank Alert');
      await tester.enterText(contentField, 'Rs. 500 debited, OTP is 987652');

      // Click Run AI Analysis
      final runButton = find.text('Run AI Analysis');
      await tester.ensureVisible(runButton);
      await tester.tap(runButton);
      await tester.pump();
      await tester.pumpAndSettle();

      // Ensure Post-Mortem Trace is visible in ListView
      final postMortemTrace = find.text('Post-Mortem Trace');
      await tester.ensureVisible(postMortemTrace);
      expect(postMortemTrace, findsOneWidget);

      // Verify defining feature chips are masked by default (OTP:••••, Amount:Rs.••••)
      expect(find.text('OTP:••••'), findsOneWidget);
      expect(find.text('Amount:Rs.••••'), findsOneWidget);
      expect(find.text('OTP:987652'), findsNothing);

      // Toggle privacy toggle in AppBar to show sensitive data
      final privacyToggle = find.byKey(const Key('ai_playground_privacy_toggle'));
      await tester.tap(privacyToggle);
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify cleartext chip labels appear
      expect(find.text('OTP:987652'), findsOneWidget);
      expect(find.text('Amount:Rs.500'), findsOneWidget);
      expect(find.text('OTP:••••'), findsNothing);
    });
  });
}
