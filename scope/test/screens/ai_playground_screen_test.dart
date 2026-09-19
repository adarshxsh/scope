import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/ai_playground_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationController controller;

  setUp(() {
    controller = NotificationController(isReleaseMode: false);
  });

  tearDown(() {
    controller.dispose();
  });

  group('AiPlaygroundScreen Release Mode Guard Tests', () {
    testWidgets('Renders AI Playground in debug mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiPlaygroundScreen(
            controller: controller,
            isReleaseMode: false,
          ),
        ),
      );

      expect(find.text('AI Playground (RLHF)'), findsOneWidget);
      expect(find.text('Model Post-Mortem'), findsOneWidget);
    });

    testWidgets('Shows assertion error in release mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiPlaygroundScreen(
            controller: controller,
            isReleaseMode: true,
          ),
        ),
      );

      expect(tester.takeException(), isA<AssertionError>());
    });
  });
}
