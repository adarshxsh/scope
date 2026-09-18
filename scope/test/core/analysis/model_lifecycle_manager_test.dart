import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_lifecycle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_lifecycle_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelLifecycleManager Tests', () {
    test('loadGhostAiModel falls back gracefully when dynamic directory is empty', () async {
      final result = await ModelLifecycleManager.loadGhostAiModel(
        customDirectoryPath: tempDir.path,
      );

      expect(
        result.source == ModelSource.bundledAsset || result.source == ModelSource.fallbackHeuristics,
        isTrue,
      );
    });

    test('loadGhostAiModel rejects invalid dynamic model files with bad shapes', () async {
      final badFile = File('${tempDir.path}/ghost_ai.tflite');
      await badFile.writeAsString('invalid_tflite_binary_bytes');

      final result = await ModelLifecycleManager.loadGhostAiModel(
        customDirectoryPath: tempDir.path,
      );

      // Should fail dynamic loading and fall back
      expect(result.source, isNot(equals(ModelSource.dynamicFile)));
    });

    test('loadCategoryClassifierModel returns fallback status when model file is missing', () async {
      final result = await ModelLifecycleManager.loadCategoryClassifierModel(
        customDirectoryPath: tempDir.path,
      );

      expect(result.source, equals(ModelSource.fallbackHeuristics));
      expect(result.isLoaded, isFalse);
    });
  });
}
