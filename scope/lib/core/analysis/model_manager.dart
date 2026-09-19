import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/model_metadata.dart';

enum ModelSource {
  bundled,
  dynamicStorage,
  fallback,
}

abstract class InferenceEngine {
  /// Executes inference on a 63-dimensional feature vector.
  Future<List<double>?> run(List<double> input);

  /// Returns input tensor shape (e.g. [1, 63]).
  List<int> getInputShape();

  /// Returns output tensor shape (e.g. [1, 1]).
  List<int> getOutputShape();

  /// Disposes native / engine resources.
  void dispose();

  /// Returns true if engine has been disposed.
  bool get isDisposed;
}

class TfLiteInferenceEngine implements InferenceEngine {
  final Interpreter interpreter;
  bool _isDisposed = false;

  TfLiteInferenceEngine(this.interpreter);

  @override
  Future<List<double>?> run(List<double> input) async {
    if (_isDisposed) return null;
    try {
      final inputTensor = [input];
      final outputTensor = List<double>.filled(1, 0.0).reshape([1, 1]);
      interpreter.run(inputTensor, outputTensor);
      final val = outputTensor[0][0];
      if (val is num) {
        return [val.toDouble()];
      }
      return null;
    } catch (e) {
      debugPrint('TfLiteInferenceEngine runtime error: $e');
      return null;
    }
  }

  @override
  List<int> getInputShape() {
    try {
      return interpreter.getInputTensor(0).shape;
    } catch (_) {
      return [];
    }
  }

  @override
  List<int> getOutputShape() {
    try {
      return interpreter.getOutputTensor(0).shape;
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      try {
        interpreter.close();
      } catch (e) {
        debugPrint('Error closing interpreter: $e');
      }
    }
  }

  @override
  bool get isDisposed => _isDisposed;
}

class SimulatedInferenceEngine implements InferenceEngine {
  final List<int> inputShape;
  final List<int> outputShape;
  final double Function(List<double> input)? predictHandler;
  bool _isDisposed = false;

  SimulatedInferenceEngine({
    this.inputShape = const [1, 63],
    this.outputShape = const [1, 1],
    this.predictHandler,
  });

  @override
  Future<List<double>?> run(List<double> input) async {
    if (_isDisposed) return null;
    if (predictHandler != null) {
      return [predictHandler!(input)];
    }
    return [50.0];
  }

  @override
  List<int> getInputShape() => List.unmodifiable(inputShape);

  @override
  List<int> getOutputShape() => List.unmodifiable(outputShape);

  @override
  void dispose() {
    _isDisposed = true;
  }

  @override
  bool get isDisposed => _isDisposed;
}

class HotSwapResult {
  final bool isSuccess;
  final String message;
  final ModelSource source;
  final ModelMetadata? metadata;

  const HotSwapResult({
    required this.isSuccess,
    required this.message,
    required this.source,
    this.metadata,
  });

  factory HotSwapResult.success(ModelMetadata? metadata, {String message = 'Model hot-swapped successfully'}) {
    return HotSwapResult(
      isSuccess: true,
      message: message,
      source: ModelSource.dynamicStorage,
      metadata: metadata,
    );
  }

  factory HotSwapResult.rejected(String reason, {ModelSource currentSource = ModelSource.bundled}) {
    return HotSwapResult(
      isSuccess: false,
      message: 'Hot-swap rejected: $reason',
      source: currentSource,
    );
  }
}

/// Central manager orchestrating model file resolution, schema validation,
/// atomic live hot-swapping, resource cleanup, and baseline fallback.
class ModelManager {
  static ModelManager? _instance;
  static ModelManager get instance => _instance ??= ModelManager._();

  InferenceEngine? _activeEngine;
  InferenceEngine? _baselineEngine;
  ModelMetadata? _activeMetadata;
  ModelSource _activeSource = ModelSource.bundled;
  String _activeVersion = '1.0.0-baseline';
  String? _storageDirOverride;

  static const List<int> requiredInputShape = [1, 63];
  static const int requiredFeatureCount = 63;

  ModelManager._();

  @visibleForTesting
  static void resetInstanceForTesting([ModelManager? testInstance]) {
    if (_instance != null && _instance != testInstance) {
      _instance!.dispose();
    }
    _instance = testInstance;
  }

  /// Sets custom local storage directory override (useful for testing or isolated environments).
  void setStorageDirectory(String path) {
    _storageDirOverride = path;
  }

  /// Gets the secure local application storage directory path for dynamic model binaries.
  Future<Directory> getStorageDirectory() async {
    if (_storageDirOverride != null) {
      final dir = Directory(_storageDirOverride!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(baseDir.path, 'models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      return modelsDir;
    } catch (e) {
      // Fallback for non-flutter testing environments
      final dir = Directory('/tmp/scope_models');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  }

  /// Returns whether a valid model engine is active.
  bool get isModelLoaded => _activeEngine != null && !_activeEngine!.isDisposed;

  /// Returns whether a dynamic model (from local storage) is currently active.
  bool get isDynamicModelLoaded => _activeSource == ModelSource.dynamicStorage && isModelLoaded;

  /// Exposes current active model source ('bundled', 'dynamicStorage', 'fallback').
  ModelSource get activeSource => _activeSource;

  /// Exposes current active model version.
  String get activeVersion => _activeVersion;

  /// Exposes active model metadata spec.
  ModelMetadata? get activeMetadata => _activeMetadata;

  /// Exposes reference to active inference engine.
  InferenceEngine? get activeEngine => _activeEngine;

  /// Initializes the ModelManager.
  /// Checks local dynamic storage for an updated model binary before falling back to bundled default assets.
  Future<void> initialize({InferenceEngine? baselineEngineOverride}) async {
    // 1. Initialize bundled baseline engine
    if (baselineEngineOverride != null) {
      _baselineEngine = baselineEngineOverride;
    } else {
      try {
        final interpreter = await Interpreter.fromAsset('assets/model.tflite');
        _baselineEngine = TfLiteInferenceEngine(interpreter);
      } catch (e) {
        debugPrint('ModelManager: Failed to load bundled asset interpreter: $e');
      }
    }

    _activeEngine = _baselineEngine;
    _activeMetadata = ModelMetadata.defaultBaseline();
    _activeSource = ModelSource.bundled;
    _activeVersion = _activeMetadata?.version ?? '1.0.0-baseline';

    // 2. Check local dynamic storage for dynamic model binaries
    await _resolveLocalDynamicModel();
  }

  /// Attempts to resolve and activate local dynamic model binaries from storage.
  Future<bool> _resolveLocalDynamicModel() async {
    try {
      final storageDir = await getStorageDirectory();
      final modelFile = File(p.join(storageDir.path, 'active_model.tflite'));
      final metadataFile = File(p.join(storageDir.path, 'active_model.json'));

      if (!await modelFile.exists()) {
        return false;
      }

      ModelMetadata? metadata;
      if (await metadataFile.exists()) {
        try {
          final jsonStr = await metadataFile.readAsString();
          metadata = ModelMetadata.fromJson(jsonStr);
        } catch (e) {
          debugPrint('ModelManager: Failed to parse metadata file: $e');
        }
      }

      // If metadata present, validate schema prior to engine initialization
      if (metadata != null) {
        if (!metadata.validateSchema(expectedInputShape: requiredInputShape, expectedFeatureCount: requiredFeatureCount)) {
          debugPrint('ModelManager: Dynamic model metadata schema invalid. Reverting to baseline.');
          return false;
        }
      }

      // Initialize TFLite interpreter from file
      final interpreter = Interpreter.fromFile(modelFile);
      final candidateEngine = TfLiteInferenceEngine(interpreter);

      final swapResult = await hotSwapEngine(candidateEngine, metadata: metadata);
      return swapResult.isSuccess;
    } catch (e) {
      debugPrint('ModelManager: Failed to load local dynamic model: $e');
      return false;
    }
  }

  /// Validates an inference engine's tensor shape contracts against requirements.
  bool validateEngineSchema(InferenceEngine engine, {ModelMetadata? metadata}) {
    if (metadata != null) {
      if (!metadata.validateSchema(expectedInputShape: requiredInputShape, expectedFeatureCount: requiredFeatureCount)) {
        return false;
      }
    }

    final inputShape = engine.getInputShape();
    if (inputShape.isEmpty) return false;

    // Last dimension must match required 63 features
    if (inputShape.last != requiredFeatureCount) {
      return false;
    }

    final outputShape = engine.getOutputShape();
    if (outputShape.isEmpty) return false;

    return true;
  }

  /// Performs live hot-swapping of active inference engine using atomic reference replacement.
  /// Accepts an `InferenceEngine` instance (e.g. `TfLiteInferenceEngine` or `SimulatedInferenceEngine`).
  Future<HotSwapResult> hotSwapEngine(
    InferenceEngine candidateEngine, {
    ModelMetadata? metadata,
    String? customVersion,
  }) async {
    // 1. Metadata spec validation
    if (metadata != null) {
      if (!metadata.validateSchema(expectedInputShape: requiredInputShape, expectedFeatureCount: requiredFeatureCount)) {
        candidateEngine.dispose();
        return HotSwapResult.rejected(
          'Metadata schema mismatch: expected input dimension 63, got ${metadata.inputShape}',
          currentSource: _activeSource,
        );
      }
    }

    // 2. Engine tensor shape contract validation
    if (!validateEngineSchema(candidateEngine, metadata: metadata)) {
      final actualShape = candidateEngine.getInputShape();
      candidateEngine.dispose();
      return HotSwapResult.rejected(
        'Tensor shape contract mismatch: expected input shape [1, 63], got $actualShape',
        currentSource: _activeSource,
      );
    }

    // 3. Atomic hot-swap reference replacement
    final oldEngine = _activeEngine;

    _activeEngine = candidateEngine;
    _activeMetadata = metadata ?? ModelMetadata(
      modelName: 'hot_swapped_model',
      version: customVersion ?? '2.0.0-dynamic',
      inputShape: candidateEngine.getInputShape(),
      outputShape: candidateEngine.getOutputShape(),
    );
    _activeSource = ModelSource.dynamicStorage;
    _activeVersion = _activeMetadata!.version;

    // 4. Safe resource disposal of inactive inference engine to prevent memory leaks
    if (oldEngine != null && oldEngine != _baselineEngine && !oldEngine.isDisposed) {
      // Small microtask delay ensures any in-flight sync prediction step finishes cleanly
      Future.microtask(() {
        oldEngine.dispose();
      });
    }

    return HotSwapResult.success(_activeMetadata);
  }

  /// Hot-swaps a model from local file paths or raw bytes.
  Future<HotSwapResult> hotSwapFromFile({
    required File modelFile,
    File? metadataFile,
    ModelMetadata? metadataSpec,
  }) async {
    try {
      if (!await modelFile.exists()) {
        return HotSwapResult.rejected('Model file does not exist at ${modelFile.path}', currentSource: _activeSource);
      }

      ModelMetadata? metadata = metadataSpec;
      if (metadata == null && metadataFile != null && await metadataFile.exists()) {
        final jsonStr = await metadataFile.readAsString();
        metadata = ModelMetadata.fromJson(jsonStr);
      }

      if (metadata != null && !metadata.validateSchema(expectedInputShape: requiredInputShape, expectedFeatureCount: requiredFeatureCount)) {
        return HotSwapResult.rejected(
          'Metadata validation failed: input shape ${metadata.inputShape} violates 63-dimensional contract',
          currentSource: _activeSource,
        );
      }

      final interpreter = Interpreter.fromFile(modelFile);
      final candidateEngine = TfLiteInferenceEngine(interpreter);

      return await hotSwapEngine(candidateEngine, metadata: metadata);
    } catch (e) {
      debugPrint('ModelManager: Failed hotSwapFromFile: $e');
      return HotSwapResult.rejected('Failed to load or parse model file: $e', currentSource: _activeSource);
    }
  }

  /// Executes model inference for a 63-dimensional feature vector.
  /// Reverts to active baseline model or fallback heuristic if prediction fails.
  Future<double?> predictScore(List<double> featureVector) async {
    if (featureVector.length != requiredFeatureCount) {
      debugPrint('ModelManager: Feature vector length (${featureVector.length}) != expected ($requiredFeatureCount)');
      return null;
    }

    final currentEngine = _activeEngine;
    if (currentEngine != null && !currentEngine.isDisposed) {
      try {
        final result = await currentEngine.run(featureVector);
        if (result != null && result.isNotEmpty) {
          return result.first;
        }
      } catch (e) {
        debugPrint('ModelManager: Error during active engine inference: $e');
      }
    }

    // If active dynamic model failed at runtime, attempt baseline model fallback
    if (_activeSource == ModelSource.dynamicStorage && _baselineEngine != null && !_baselineEngine!.isDisposed) {
      debugPrint('ModelManager: Active dynamic engine failed. Falling back to baseline model.');
      await revertToBaseline();
      final baselineResult = await _baselineEngine!.run(featureVector);
      if (baselineResult != null && baselineResult.isNotEmpty) {
        return baselineResult.first;
      }
    }

    return null;
  }

  /// Reverts active model to bundled baseline model.
  Future<void> revertToBaseline() async {
    if (_activeEngine != null && _activeEngine != _baselineEngine && !_activeEngine!.isDisposed) {
      _activeEngine!.dispose();
    }
    _activeEngine = _baselineEngine;
    _activeSource = ModelSource.bundled;
    _activeMetadata = ModelMetadata.defaultBaseline();
    _activeVersion = _activeMetadata!.version;
  }

  /// Disposes all managed engines and clears state.
  void dispose() {
    if (_activeEngine != null && !_activeEngine!.isDisposed) {
      _activeEngine!.dispose();
    }
    if (_baselineEngine != null && _baselineEngine != _activeEngine && !_baselineEngine!.isDisposed) {
      _baselineEngine!.dispose();
    }
    _activeEngine = null;
    _baselineEngine = null;
    _activeMetadata = null;
    _activeSource = ModelSource.fallback;
    _activeVersion = 'fallback-heuristics';
  }
}
