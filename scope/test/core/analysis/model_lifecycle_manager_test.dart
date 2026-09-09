import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/analysis/model_lifecycle_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('model_manager_test_');
    ModelLifecycleManager.instance.setCustomActiveDirectory(tempDir.path);
  });

  tearDown(() {
    ModelLifecycleManager.instance.setCustomActiveDirectory(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ModelLifecycleManager Unit Tests', () {
    test('validateContract correctly validates shape and feature version', () {
      const validContract = ModelContract(
        featureVersion: 1,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      expect(
        ModelLifecycleManager.instance.validateContract(
          validContract,
          ModelLifecycleManager.defaultGhostAiContract,
        ),
        isTrue,
      );

      const invalidShapeContract = ModelContract(
        featureVersion: 1,
        inputShape: [1, 50],
        outputShape: [1, 1],
      );

      expect(
        ModelLifecycleManager.instance.validateContract(
          invalidShapeContract,
          ModelLifecycleManager.defaultGhostAiContract,
        ),
        isFalse,
      );

      const invalidVersionContract = ModelContract(
        featureVersion: 2,
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      expect(
        ModelLifecycleManager.instance.validateContract(
          invalidVersionContract,
          ModelLifecycleManager.defaultGhostAiContract,
        ),
        isFalse,
      );
    });

    test('deployModelPackage writes binary and manifest to active directory', () async {
      final mockManifest = {
        'feature_version': 1,
        'input_shape': [1, 63],
        'output_shape': [1, 1],
        'compatibility_hash': 'test_hash_123',
      };

      final mockBytes = List<int>.generate(100, (i) => i % 256);

      final success = await ModelLifecycleManager.instance.deployModelPackage(
        modelName: ModelLifecycleManager.ghostAiModelName,
        tfliteBytes: mockBytes,
        manifest: mockManifest,
      );

      expect(success, isTrue);

      final deployedBinary = File(p.join(tempDir.path, 'ghost_ai.tflite'));
      expect(deployedBinary.existsSync(), isTrue);
      expect(deployedBinary.readAsBytesSync().length, equals(100));

      final manifestFile = File(p.join(tempDir.path, 'model_manifest.json'));
      expect(manifestFile.existsSync(), isTrue);

      final loadedManifest = await ModelLifecycleManager.instance.loadManifest();
      expect(loadedManifest, isNotNull);
      expect(loadedManifest!['ghost_ai']['compatibility_hash'], equals('test_hash_123'));
    });
  });
}
