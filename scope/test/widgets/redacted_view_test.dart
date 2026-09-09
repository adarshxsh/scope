import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/widgets/redacted_view.dart';

void main() {
  group('RedactedView Widget Tests', () {
    testWidgets('renders masked value by default and reveals cleartext on tap toggle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RedactedView(
              value: '882715',
              maskedValue: '****15',
              label: 'OTP Code',
            ),
          ),
        ),
      );

      // Verify default state is masked
      expect(find.text('****15'), findsOneWidget);
      expect(find.text('882715'), findsNothing);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap to reveal cleartext
      await tester.tap(find.byType(RedactedView));
      await tester.pumpAndSettle();

      // Verify revealed state shows cleartext
      expect(find.text('882715'), findsOneWidget);
      expect(find.text('****15'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Tap again to re-mask
      await tester.tap(find.byType(RedactedView));
      await tester.pumpAndSettle();

      // Verify re-masked state
      expect(find.text('****15'), findsOneWidget);
      expect(find.text('882715'), findsNothing);
    });

    testWidgets('custom builder mode supports toggling and custom UI rendering', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RedactedView(
              value: 'Rs. 5000',
              maskedValue: 'Rs. ***0',
              builder: (context, isRedacted, displayText) => Chip(
                label: Text('Amount: $displayText'),
              ),
            ),
          ),
        ),
      );

      // Verify default custom builder state
      expect(find.text('Amount: Rs. ***0'), findsOneWidget);
      expect(find.text('Amount: Rs. 5000'), findsNothing);

      // Tap custom chip widget
      await tester.tap(find.byType(Chip));
      await tester.pumpAndSettle();

      // Verify revealed state in custom builder
      expect(find.text('Amount: Rs. 5000'), findsOneWidget);
      expect(find.text('Amount: Rs. ***0'), findsNothing);
    });
  });
}
