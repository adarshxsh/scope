// Smoke test for the AttentionOS app root widget.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/main.dart';

void main() {
  testWidgets('AttentionOSApp renders without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AttentionOSApp()));
    await tester.pump();

    // Verify home dashboard renders
    expect(find.text('Home'), findsOneWidget);
  });
}
