import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/ai_playground_screen.dart';

class FakeNotificationController extends NotificationController {
  FakeNotificationController() : super(engine: GhostAnalysisEngine());

  @override
  List<AppNotification> get notifications => [
        const AppNotification(
          id: 'test-1',
          packageName: 'com.sbi.upi',
          title: 'SBI Alert',
          content: 'Rs. 5000 debited from a/c 1234. OTP is 443322.',
          timestamp: 1700000000000,
          priority: 'high',
          classifiedCategory: 'finance',
          explanation: 'OTP code 443322 detected.',
          extractedFeatures: {
            'otp': '443322',
            'amount': 5000.0,
          },
        ),
      ];
}

void main() {
  group('AiPlaygroundScreen Privacy Tests', () {
    late NotificationController controller;

    setUp(() {
      controller = FakeNotificationController();
    });

    testWidgets('AiPlaygroundScreen redacts PII by default and reveals cleartext when toggled',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiPlaygroundScreen(controller: controller),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the recent notification card to open post-mortem panel
      final itemFinder = find.text('com.sbi.upi');
      expect(itemFinder, findsOneWidget);
      await tester.tap(itemFinder);
      await tester.pumpAndSettle();

      // Verify Post-Mortem Trace panel is shown
      expect(find.text('Post-Mortem Trace'), findsOneWidget);

      // Verify PII is redacted by default in tags and content
      expect(find.textContaining('[REDACTED_OTP]'), findsWidgets);
      expect(find.textContaining('[REDACTED_AMOUNT]'), findsWidgets);

      // Verify cleartext OTP is NOT visible when redacted
      expect(find.text('443322'), findsNothing);

      // Toggle Show Sensitive Data switch on
      final switchFinder = find.byType(Switch).first;
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Verify cleartext is now visible when toggled
      expect(find.textContaining('443322'), findsWidgets);
    });
  });
}
