import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/ai_playground_screen.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'critical',
      priorityScore: 0.95,
      classifiedCategory: 'financial',
      explanation: 'Account debited Rs. 5000 using OTP 654321.',
      latencyMs: 2,
      extractedFeatures: const {
        'otp': '654321',
        'amount': 5000.0,
        'hasDeadline': false,
        'urls': [],
        'emails': [],
        'phoneNumbers': [],
      },
    );
  }
}

void main() {
  group('AiPlaygroundScreen Privacy Masking Tests', () {
    late ProviderContainer container;
    late NotificationController mockController;

    setUp(() {
      container = ProviderContainer();
      final storage = InMemoryNotificationStorage();
      mockController = NotificationController(
        storage: storage,
        engine: FakeGhostAnalysisEngine(),
        container: container,
      );

      container.read(reviewQueueProvider.notifier).load([
        const AppNotification(
          id: 'test_1',
          packageName: 'com.hdfc.bank',
          title: 'HDFC Alert',
          content: 'Your account was debited Rs. 2,500 using code 987123.',
          timestamp: 100000,
          classifiedCategory: 'financial',
          priority: 'critical',
          explanation: 'Found OTP code 987123 and amount Rs. 2,500.',
          extractedFeatures: {
            'otp': '987123',
            'amount': 2500.0,
            'hasDeadline': false,
            'urls': [],
            'emails': [],
            'phoneNumbers': [],
          },
        ),
      ]);
    });

    testWidgets('AiPlaygroundScreen renders masked text when privacy mode is ON', (WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AiPlaygroundScreen(controller: mockController),
          ),
        ),
      );

      // Select recent notification card
      await tester.tap(find.text('HDFC Alert'));
      await tester.pumpAndSettle();

      // Post-Mortem Trace section should display masked values
      expect(find.text('Post-Mortem Trace'), findsOneWidget);
      expect(find.textContaining('[REDACTED OTP]'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Rs. [HIDDEN]'), findsAtLeastNWidgets(1));

      // Toggle Privacy Mode OFF
      final privacyToggle = find.byIcon(Icons.visibility_off);
      expect(privacyToggle, findsOneWidget);
      await tester.tap(privacyToggle);
      await tester.pumpAndSettle();

      // Unmasked raw values should now be visible
      expect(find.textContaining('987123'), findsAtLeastNWidgets(1));
      expect(find.textContaining('2500'), findsAtLeastNWidgets(1));
    });
  });
}
