import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {} // No-op, do not load assets in test

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'critical',
      priorityScore: 0.99,
      classifiedCategory: 'sys',
      explanation: 'OTP Code: Found verification code 987652.',
      latencyMs: 1,
      extractedFeatures: const {
        'otp': '987652',
        'amount': null,
        'hasDeadline': false,
        'urls': [],
        'emails': [],
        'phoneNumbers': [],
      },
    );
  }
}

void main() {
  group('DiagnosticScreen Widget Tests', () {
    late GhostAnalysisEngine mockEngine;

    setUp(() {
      mockEngine = FakeGhostAnalysisEngine();
    });

    testWidgets('DiagnosticScreen renders successfully and can select template',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticScreen(engine: mockEngine),
          ),
        ),
      );

      // Verify basic titles load
      expect(find.text('Ghost AI Diagnostics'), findsOneWidget);
      expect(find.text('Input Notification Spec'), findsOneWidget);
      expect(find.text('ANALYZE NOTIFICATION'), findsOneWidget);

      // Apply template selection
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Find the dropdown option for HDFC Debit
      final option = find.text('HDFC Bank Debit Alert').last;
      await tester.tap(option);
      await tester.pumpAndSettle();

      // Verify that fields have been populated by the template
      final packageField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'Package Name',
      );
      expect(tester.widget<TextField>(packageField).controller?.text,
          equals('com.hdfc.mobilebanking'));

      final contentField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'Content Body',
      );
      expect(
        tester.widget<TextField>(contentField).controller?.text,
        contains('debit'),
      );
    });

    testWidgets('triggers analysis and shows results cards', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticScreen(engine: mockEngine),
          ),
        ),
      );

      // Set input fields directly
      final contentFieldFinder = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'Content Body',
      );
      await tester.enterText(contentFieldFinder, 'Your verification OTP is 987652');
      
      final titleFieldFinder = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.enterText(titleFieldFinder, 'Verification');

      final packageFieldFinder = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'Package Name',
      );
      await tester.enterText(packageFieldFinder, 'com.whatsapp');

      // Click analyze
      await tester.tap(find.text('ANALYZE NOTIFICATION'));
      await tester.pumpAndSettle();

      // Verify result dashboard cards appear
      expect(find.text('Analysis Pipeline Results'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('Pipeline Explanation Trace'), findsOneWidget);
      expect(find.text('Extracted Text Features'), findsOneWidget);
    });
  });
}
