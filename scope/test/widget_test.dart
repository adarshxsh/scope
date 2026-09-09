// Smoke test for the AttentionOS app root widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/main.dart';


void main() {
  testWidgets('AttentionOSApp renders without crashing', (tester) async {
    await tester.pumpWidget(const AttentionOSApp());
    await tester.pumpAndSettle();

    // Verify home dashboard renders
    expect(find.text('Home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

}
