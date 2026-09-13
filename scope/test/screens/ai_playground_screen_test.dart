import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/ai_playground_screen.dart';

class FakeNotificationController extends NotificationController {
  final List<AppNotification> _testNotifications = [];

  FakeNotificationController() : super(engine: FakeGhostEngine());

  void addTestNotification(AppNotification n) {
    _testNotifications.add(n);
    notifyListeners();
  }

  @override
  List<AppNotification> get notifications => List.unmodifiable(_testNotifications);
}

class FakeGhostEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'high',
      classifiedCategory: 'financial',
      explanation: 'Financial alert with OTP and amount.',
      latencyMs: 5,
      extractedFeatures: const {
        'otp': '882715',
        'amount': 5000.0,
      },
    );
  }
}

void main() {
  group('AiPlaygroundScreen Widget Tests', () {
    late NotificationController controller;

    setUp(() {
      controller = FakeNotificationController();
      (controller as FakeNotificationController).addTestNotification(
        AppNotification(
          id: 'n-ai-1',
          packageName: 'com.sbi.upi',
          title: 'Debit Alert',
          content: 'Rs.5000 debited OTP 882715',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          priority: 'high',
          classifiedCategory: 'financial',
          extractedFeatures: const {
            'otp': '882715',
            'amount': 5000.0,
          },
        ),
      );
    });

    testWidgets('renders masked chips by default and unmasks on toggle', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiPlaygroundScreen(controller: controller),
          ),
        ),
      );

      // Tap on recent notification card to show post-mortem trace panel
      await tester.tap(find.text('Debit Alert'));
      await tester.pumpAndSettle();

      // Verify post-mortem trace is visible
      expect(find.text('Post-Mortem Trace'), findsOneWidget);

      // Verify masked chips by default
      expect(find.text('OTP:88****'), findsOneWidget);
      expect(find.text('Amount:Rs.****'), findsOneWidget);
      expect(find.text('OTP:882715'), findsNothing);

      // Toggle unmask switch
      final toggleFinder = find.byKey(const Key('ai_playground_unmask_toggle'));
      await tester.ensureVisible(toggleFinder);
      await tester.pumpAndSettle();
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      // Verify unmasked cleartext values appear
      expect(find.text('OTP:882715'), findsOneWidget);
      expect(find.text('Amount:Rs.5000.0'), findsOneWidget);
    });
  });
}
