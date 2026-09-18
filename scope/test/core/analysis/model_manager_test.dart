import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_manager.dart';
import 'package:scope/core/analysis/model_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelMetadata Schema Validation Tests', () {
    test('validates correct 63-dimensional tensor input shape', () {
      final metadata = ModelMetadata(
        modelName: 'test_model',
        version: '1.0.0',
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      expect(metadata.validateSchema(), isTrue);
    });

    test('rejects mismatched input tensor dimensions (e.g. 64-dim vector)', () {
      final metadata = ModelMetadata(
        modelName: 'mismatched_model',
        version: '2.0.0',
        inputShape: [1, 64],
        outputShape: [1, 1],
      );

      expect(metadata.validateSchema(), isFalse);
    });

    test('rejects invalid or empty tensor shapes', () {
      final emptyInput = ModelMetadata(
        modelName: 'empty_input',
        version: '1.0.0',
        inputShape: [],
        outputShape: [1, 1],
      );

      final emptyOutput = ModelMetadata(
        modelName: 'empty_output',
        version: '1.0.0',
        inputShape: [1, 63],
        outputShape: [],
      );

      expect(emptyInput.validateSchema(), isFalse);
      expect(emptyOutput.validateSchema(), isFalse);
    });

    test('parses json metadata correctly and preserves contracts', () {
      const jsonStr = '''
      {
        "model_name": "ghost_ai_v2",
        "version": "2.1.0",
        "input_tensor": {
          "name": "features",
          "shape": [1, 63],
          "type": "float32"
        },
        "output_tensor": {
          "name": "score",
          "shape": [1, 1],
          "type": "float32"
        }
      }
      ''';

      final metadata = ModelMetadata.fromJson(jsonStr);
      expect(metadata.modelName, equals('ghost_ai_v2'));
      expect(metadata.version, equals('2.1.0'));
      expect(metadata.inputShape, equals([1, 63]));
      expect(metadata.outputShape, equals([1, 1]));
      expect(metadata.validateSchema(), isTrue);
    });
  });

  group('ModelManager Unit & Hot-Swap Tests', () {
    late ModelManager manager;

    setUp(() async {
      manager = ModelManager.instance;
      ModelManager.resetInstanceForTesting(manager);

      final baselineEngine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        outputShape: [1, 1],
        predictHandler: (features) => 35.0,
      );

      await manager.initialize(baselineEngineOverride: baselineEngine);
    });

    tearDown(() {
      manager.dispose();
    });

    test('initializes with baseline engine bundled fallback', () {
      expect(manager.isModelLoaded, isTrue);
      expect(manager.activeSource, equals(ModelSource.bundled));
      expect(manager.activeVersion, equals('1.0.0-baseline'));
    });

    test('performs live runtime hot-swapping without app restart', () async {
      final v2Engine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        outputShape: [1, 1],
        predictHandler: (features) => 95.0,
      );

      final v2Metadata = ModelMetadata(
        modelName: 'v2_updated_model',
        version: '2.0.0-dynamic',
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      final result = await manager.hotSwapEngine(v2Engine, metadata: v2Metadata);

      expect(result.isSuccess, isTrue);
      expect(manager.isDynamicModelLoaded, isTrue);
      expect(manager.activeSource, equals(ModelSource.dynamicStorage));
      expect(manager.activeVersion, equals('2.0.0-dynamic'));

      final score = await manager.predictScore(List<double>.filled(63, 1.0));
      expect(score, equals(95.0));
    });

    test('rejects 100% of candidate models violating 63-dimensional tensor contract', () async {
      final invalid64Engine = SimulatedInferenceEngine(
        inputShape: [1, 64], // Invalid shape
        outputShape: [1, 1],
        predictHandler: (features) => 80.0,
      );

      final invalidMetadata = ModelMetadata(
        modelName: 'invalid_shape_model',
        version: '9.9.9',
        inputShape: [1, 64],
        outputShape: [1, 1],
      );

      final result = await manager.hotSwapEngine(invalid64Engine, metadata: invalidMetadata);

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('schema mismatch'));
      // Active model source remains untouched
      expect(manager.activeSource, equals(ModelSource.bundled));
      expect(manager.activeVersion, equals('1.0.0-baseline'));
      // Invalid engine disposed
      expect(invalid64Engine.isDisposed, isTrue);
    });

    test('safely disposes inactive engine resources after hot-swap', () async {
      final v2Engine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        predictHandler: (features) => 50.0,
      );

      await manager.hotSwapEngine(v2Engine, customVersion: '2.0.0');
      expect(v2Engine.isDisposed, isFalse);

      final v3Engine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        predictHandler: (features) => 75.0,
      );

      await manager.hotSwapEngine(v3Engine, customVersion: '3.0.0');

      // Allow microtask disposal to complete
      await Future.delayed(Duration.zero);

      // Inactive v2 engine must be disposed
      expect(v2Engine.isDisposed, isTrue);
      expect(v3Engine.isDisposed, isFalse);
      expect(manager.activeVersion, equals('3.0.0'));
    });

    test('maintains zero downtime during active background notification processing', () async {
      final initialEngine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        predictHandler: (features) {
          // Simulate short processing time
          return 40.0;
        },
      );

      await manager.hotSwapEngine(initialEngine, customVersion: '1.5.0');

      // Trigger parallel inference requests while initiating a hot-swap
      final dummyFeatures = List<double>.filled(63, 0.5);

      final pendingRequest1 = manager.predictScore(dummyFeatures);
      final pendingRequest2 = manager.predictScore(dummyFeatures);

      // Perform hot-swap concurrently
      final v2Engine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        predictHandler: (features) => 85.0,
      );
      final swapFuture = manager.hotSwapEngine(v2Engine, customVersion: '2.0.0');

      final pendingRequest3 = manager.predictScore(dummyFeatures);

      final results = await Future.wait([pendingRequest1, pendingRequest2, swapFuture, pendingRequest3]);

      final r1 = results[0] as double?;
      final r2 = results[1] as double?;
      final swapResult = results[2] as HotSwapResult;
      final r3 = results[3] as double?;

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(swapResult.isSuccess, isTrue);
      expect(r3, equals(85.0));
      expect(manager.activeVersion, equals('2.0.0'));
    });

    test('reverts automatically to baseline model when dynamic execution fails', () async {
      final failingEngine = SimulatedInferenceEngine(
        inputShape: [1, 63],
        predictHandler: (features) {
          throw Exception('Model inference crashed');
        },
      );

      await manager.hotSwapEngine(failingEngine, customVersion: 'failing-v1');
      expect(manager.activeSource, equals(ModelSource.dynamicStorage));

      // Execution attempt should catch error and revert to baseline
      final dummyFeatures = List<double>.filled(63, 1.0);
      final score = await manager.predictScore(dummyFeatures);

      // Baseline engine produces score 35.0
      expect(score, equals(35.0));
      expect(manager.activeSource, equals(ModelSource.bundled));
      expect(manager.activeVersion, equals('1.0.0-baseline'));
    });

    test('revertToBaseline manually restores baseline model state', () async {
      final customEngine = SimulatedInferenceEngine(inputShape: [1, 63]);
      await manager.hotSwapEngine(customEngine, customVersion: 'custom-v1');
      expect(manager.activeSource, equals(ModelSource.dynamicStorage));

      await manager.revertToBaseline();

      expect(manager.activeSource, equals(ModelSource.bundled));
      expect(manager.activeVersion, equals('1.0.0-baseline'));
      expect(customEngine.isDisposed, isTrue);
    });
  });
}
