import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/screens/ai_playground_screen.dart';

void main() {
  late AttentionDatabase db;
  late ProviderContainer container;
  late NotificationController controller;

  setUp(() {
    db = AttentionDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
    controller = NotificationController(container: container);
  });

  tearDown(() async {
    controller.dispose();
    container.dispose();
    await db.close();
  });

  group('AiPlaygroundScreen RLHF Tests', () {
    testWidgets('Submitting Reward inserts feedback record into MlFeedbackTable', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: AiPlaygroundScreen(controller: controller),
            ),
          ),
        ),
      );

      // Select Simulator Mode ChoiceChip
      final simulatorChipFinder = find.widgetWithText(ChoiceChip, 'Simulator Mode');
      await tester.tap(simulatorChipFinder);
      await tester.pumpAndSettle();

      // Enter custom notification text and run live inference
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'com.whatsapp');
      await tester.enterText(fields.at(1), 'Security Code');
      await tester.enterText(fields.at(2), 'Your OTP is 123456');

      final runButtonFinder = find.widgetWithText(ElevatedButton, 'Run AI Analysis');
      await tester.tap(runButtonFinder);
      await tester.pumpAndSettle();

      // Scroll down to expose post-mortem panel and Reward button
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      final rewardButtonFinder = find.text('Reward (+1)');
      expect(rewardButtonFinder, findsOneWidget);

      await tester.tap(rewardButtonFinder);
      await tester.pumpAndSettle();

      // Verify feedback was persisted in database
      final feedbackEntries = await controller.db.mlFeedbackDao.getAll();
      expect(feedbackEntries.length, equals(1));
      expect(feedbackEntries.first.rewardScore, equals(1.0));
      expect(feedbackEntries.first.packageName, equals('com.whatsapp'));
    });
  });
}
