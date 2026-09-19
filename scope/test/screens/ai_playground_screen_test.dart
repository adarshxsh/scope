import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/analysis/model_lifecycle_manager.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/ai_playground_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_playground_test_');
    ModelLifecycleManager.instance.setCustomBaseDirectory(tempDir);
    await ModelLifecycleManager.instance.clearFeedbackSamples();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('AiPlaygroundScreen renders and logs RLHF sample on Reward button press', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = InMemoryNotificationStorage();
    final engine = GhostAnalysisEngine();
    final controller = NotificationController(storage: storage, engine: engine);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AiPlaygroundScreen(controller: controller),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Select Simulator Mode ChoiceChip
    final simChip = find.text('Simulator Mode');
    expect(simChip, findsOneWidget);
    await tester.tap(simChip);
    await tester.pumpAndSettle();

    // Enter title and content
    await tester.enterText(find.byType(TextField).at(0), 'com.whatsapp');
    await tester.enterText(find.byType(TextField).at(1), 'WhatsApp Code');
    await tester.enterText(find.byType(TextField).at(2), 'Your verification code is 123456');

    // Tap Run AI Analysis button
    final analyzeBtn = find.text('Run AI Analysis');
    expect(analyzeBtn, findsOneWidget);
    await tester.tap(analyzeBtn);
    await tester.pumpAndSettle();

    // Tap Reward (+1) button
    final rewardBtn = find.text('Reward (+1)');
    expect(rewardBtn, findsOneWidget);
    await tester.tap(rewardBtn, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify RLHF sample was logged in ModelLifecycleManager
    expect(ModelLifecycleManager.instance.feedbackSamplesCount, 1);
    final sample = ModelLifecycleManager.instance.feedbackSamples.first;
    expect(sample.packageName, 'com.whatsapp');
    expect(sample.rewardSignal, 1.0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
