import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_lifecycle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_lifecycle_test_');
    ModelLifecycleManager.instance.setCustomActiveDirectory(tempDir.path);
  });

  tearDown(() async {
    ModelLifecycleManager.instance.disposeInterpreters();
    ModelLifecycleManager.instance.setCustomActiveDirectory(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelLifecycleManager Contract & Validation Tests', () {
    test('validateContract returns true for matching contracts', () {
      const contract = ModelContract(
        featureVersion: 1,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );
      const expected = ModelContract(
        featureVersion: 1,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      final isValid = ModelLifecycleManager.instance.validateContract(contract, expected);
      expect(isValid, isTrue);
    });

    test('validateContract returns false on feature version mismatch', () {
      const contract = ModelContract(
        featureVersion: 2,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );
      const expected = ModelContract(
        featureVersion: 1,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      final isValid = ModelLifecycleManager.instance.validateContract(contract, expected);
      expect(isValid, isFalse);
    });

    test('validateContract returns false on shape mismatch', () {
      const contract = ModelContract(
        featureVersion: 1,
        inputShape: [1, 128],
        outputShape: [1, 1],
      );
      const expected = ModelContract(
        featureVersion: 1,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      final isValid = ModelLifecycleManager.instance.validateContract(contract, expected);
      expect(isValid, isFalse);
    });

    test('loadGhostAiModel falls back gracefully when directory is empty or file corrupt', () async {
      // Create empty/corrupt model file
      final corruptFile = File('${tempDir.path}/ghost_ai.tflite');
      await corruptFile.writeAsString('invalid binary content');

      final result = await ModelLifecycleManager.instance.loadGhostAiModel(
        customDirectoryPath: tempDir.path,
      );

      // Should fall back to asset or heuristics without throwing exception
      expect(result.source, isNot(equals(ModelSource.dynamicFile)));
    });

    test('deployModelPackage writes model binary and manifest', () async {
      final success = await ModelLifecycleManager.instance.deployModelPackage(
        modelName: 'ghost_ai',
        tfliteBytes: [1, 2, 3, 4],
        manifest: {
          'feature_version': 1,
          'input_shape': [1, 63],
          'output_shape': [1, 1],
        },
      );

      expect(success, isTrue);
      final modelFile = File('${tempDir.path}/ghost_ai.tflite');
      final manifestFile = File('${tempDir.path}/model_manifest.json');
      expect(await modelFile.exists(), isTrue);
      expect(await manifestFile.exists(), isTrue);
    });
  });
}
