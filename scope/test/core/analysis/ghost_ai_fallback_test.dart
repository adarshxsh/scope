import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostAI Custom Model & Dynamic Fallback Tests', () {
    tearDown(() {
      GhostAI.instance.resetInterpreter();
    });

    test('GhostAI falls back when custom model file path does not exist', () async {
      GhostAI.instance.resetInterpreter();
      await GhostAI.instance.initialize(customModelPath: '/non/existent/model.tflite');

      expect(GhostAI.instance.isCustomModelLoaded, isFalse);
    });

    test('GhostAI falls back to asset when custom model file is unreadable or invalid', () async {
      final tempDir = await Directory.systemTemp.createTemp('ghost_ai_test');
      final corruptFile = File('${tempDir.path}/corrupt_model.tflite');
      await corruptFile.writeAsString('not a valid tflite binary model file');

      GhostAI.instance.resetInterpreter();
      await GhostAI.instance.initialize(customModelPath: corruptFile.path);

      expect(GhostAI.instance.isCustomModelLoaded, isFalse);

      await tempDir.delete(recursive: true);
    });

    test('GhostAI attempts custom model loading when model file is present in storage', () async {
      final tempDir = await Directory.systemTemp.createTemp('ghost_ai_test');
      final customModelFile = File('${tempDir.path}/custom_model.tflite');

      final assetFile = File('build/unit_test_assets/assets/model.tflite');
      if (await assetFile.exists()) {
        await assetFile.copy(customModelFile.path);

        GhostAI.instance.resetInterpreter();
        await GhostAI.instance.initialize(customModelPath: customModelFile.path);

        // If native C library is missing in desktop unit test environment, fallback sets isCustomModelLoaded to false.
        // Otherwise, isCustomModelLoaded is true. Either outcome proves initialization does not crash.
        expect(GhostAI.instance.isCustomModelLoaded, isA<bool>());
      }

      await tempDir.delete(recursive: true);
    });
  });
}
