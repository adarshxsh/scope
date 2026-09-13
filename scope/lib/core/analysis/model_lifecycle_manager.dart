import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Active source origin for an ML model interpreter.
enum ModelSource {
  dynamicFile,
  bundledAsset,
  fallbackHeuristics,
}

/// Contract specification for expected model tensor shapes and versions.
class ModelContract {
  final int featureVersion;
  final List<int> inputShape;
  final List<int> outputShape;
  final String? compatibilityHash;

  const ModelContract({
    required this.featureVersion,
    required this.inputShape,
    required this.outputShape,
    this.compatibilityHash,
  });

  factory ModelContract.fromJson(Map<String, dynamic> json) {
    return ModelContract(
      featureVersion: (json['feature_version'] as num?)?.toInt() ?? 1,
      inputShape: (json['input_shape'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [],
      outputShape: (json['output_shape'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [],
      compatibilityHash: json['compatibility_hash'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'feature_version': featureVersion,
        'input_shape': inputShape,
        'output_shape': outputShape,
        if (compatibilityHash != null) 'compatibility_hash': compatibilityHash,
      };
}

/// Result of a model load request containing interpreter instance and lifecycle metadata.
class ModelLoadResult {
  final Interpreter? interpreter;
  final ModelSource source;
  final String version;
  final String? filePath;
  final String? error;
  final bool isValidated;

  const ModelLoadResult({
    this.interpreter,
    required this.source,
    required this.version,
    this.filePath,
    this.error,
    this.isValidated = false,
  });

  bool get isLoaded => interpreter != null;
}

/// Dynamic Model Registry and Manager handling local TFLite binaries,
/// contract validation, shape inspection, hot-swapping, and asset fallbacks.
class ModelLifecycleManager {
  static ModelLifecycleManager? _instance;
  static ModelLifecycleManager get instance => _instance ??= ModelLifecycleManager._();

  ModelLifecycleManager._();

  static const String ghostAiModelName = 'ghost_ai';
  static const String textClassifierModelName = 'text_classifier';
  static const String defaultGhostAiAssetPath = 'assets/model.tflite';
  static const String defaultClassifierAssetPath = 'assets/text_classifier.tflite';

  static const ModelContract defaultGhostAiContract = ModelContract(
    featureVersion: 1,
    inputShape: [1, 63],
    outputShape: [1, 1],
  );

  static const ModelContract defaultTextClassifierContract = ModelContract(
    featureVersion: 1,
    inputShape: [1, 64],
    outputShape: [1, 5],
  );

  String? _customActiveDirectory;
  Interpreter? _activeGhostAiInterpreter;
  Interpreter? _activeClassifierInterpreter;

  /// Override active models directory (useful for testing).
  void setCustomActiveDirectory(String? path) {
    _customActiveDirectory = path;
  }

  /// Gets the local active models directory (`<app_docs>/models/active/`).
  Future<Directory?> getActiveModelDirectory() async {
    if (_customActiveDirectory != null) {
      final dir = Directory(_customActiveDirectory!);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final activeDir = Directory(p.join(docsDir.path, 'models', 'active'));
      if (!activeDir.existsSync()) {
        activeDir.createSync(recursive: true);
      }
      return activeDir;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Unable to resolve active model directory: $e');
      return null;
    }
  }

  /// Loads and parses model manifest from local active storage or default assets.
  Future<Map<String, dynamic>?> loadManifest() async {
    try {
      final activeDir = await getActiveModelDirectory();
      if (activeDir != null) {
        final localManifestFile = File(p.join(activeDir.path, 'model_manifest.json'));
        if (localManifestFile.existsSync()) {
          try {
            final content = await localManifestFile.readAsString();
            return jsonDecode(content) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('ModelLifecycleManager: Failed to parse local model_manifest.json: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error accessing local manifest: $e');
    }

    try {
      final content = await rootBundle.loadString('assets/model_manifest.json');
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Asset model_manifest.json unavailable: $e');
      return null;
    }
  }

  /// Validates a model contract against expected specification.
  bool validateContract(ModelContract contract, ModelContract expected) {
    if (contract.featureVersion != expected.featureVersion) {
      debugPrint('ModelLifecycleManager contract mismatch: featureVersion '
          '(${contract.featureVersion} vs expected ${expected.featureVersion})');
      return false;
    }

    if (!listEquals(contract.inputShape, expected.inputShape)) {
      debugPrint('ModelLifecycleManager contract mismatch: inputShape '
          '(${contract.inputShape} vs expected ${expected.inputShape})');
      return false;
    }

    if (!listEquals(contract.outputShape, expected.outputShape)) {
      debugPrint('ModelLifecycleManager contract mismatch: outputShape '
          '(${contract.outputShape} vs expected ${expected.outputShape})');
      return false;
    }

    return true;
  }

  /// Loads GhostAI look-again model dynamically, with validation and asset fallback.
  Future<ModelLoadResult> loadGhostAiModel({
    String? customDirectoryPath,
    ModelContract expectedContract = defaultGhostAiContract,
  }) async {
    // 1. Check dynamic local directory
    try {
      final activeDir = customDirectoryPath != null
          ? Directory(customDirectoryPath)
          : await getActiveModelDirectory();

      if (activeDir != null && await activeDir.exists()) {
        final candidateNames = ['ghost_ai.tflite', 'model.tflite'];
        for (final fileName in candidateNames) {
          final file = File(p.join(activeDir.path, fileName));
          if (await file.exists()) {
            final len = await file.length();
            if (len > 0) {
              final result = await _tryLoadFromFile(
                file,
                expectedContract: expectedContract,
                modelName: ghostAiModelName,
              );
              if (result != null && result.isLoaded) {
                _swapInterpreter(ghostAiModelName, result.interpreter);
                return result;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Dynamic GhostAI inspection failed: $e');
    }

    // 2. Bundled Asset Fallback
    try {
      final assetInterpreter = await Interpreter.fromAsset(defaultGhostAiAssetPath);
      if (_verifyInterpreterShapes(assetInterpreter, expectedContract)) {
        debugPrint('ModelLifecycleManager: Loaded bundled asset for GhostAI.');
        _swapInterpreter(ghostAiModelName, assetInterpreter);
        return ModelLoadResult(
          interpreter: assetInterpreter,
          source: ModelSource.bundledAsset,
          version: '1.0.0-asset',
          filePath: defaultGhostAiAssetPath,
          isValidated: true,
        );
      } else {
        assetInterpreter.close();
        debugPrint('ModelLifecycleManager: Bundled asset shape verification failed for GhostAI.');
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Bundled GhostAI asset load failed: $e');
    }

    // 3. Heuristic Fallback
    return const ModelLoadResult(
      interpreter: null,
      source: ModelSource.fallbackHeuristics,
      version: 'fallback-heuristics',
      isValidated: false,
    );
  }

  /// Loads Category Classifier model dynamically, with validation and fallback.
  Future<ModelLoadResult> loadCategoryClassifierModel({
    String? customDirectoryPath,
    ModelContract expectedContract = defaultTextClassifierContract,
  }) async {
    // 1. Local dynamic check
    try {
      final activeDir = customDirectoryPath != null
          ? Directory(customDirectoryPath)
          : await getActiveModelDirectory();

      if (activeDir != null && await activeDir.exists()) {
        final file = File(p.join(activeDir.path, 'text_classifier.tflite'));
        if (await file.exists() && await file.length() > 0) {
          final result = await _tryLoadFromFile(
            file,
            expectedContract: expectedContract,
            modelName: textClassifierModelName,
          );
          if (result != null && result.isLoaded) {
            _swapInterpreter(textClassifierModelName, result.interpreter);
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Dynamic classifier inspection failed: $e');
    }

    // 2. Asset fallback
    try {
      final assetInterpreter = await Interpreter.fromAsset(defaultClassifierAssetPath);
      if (_verifyInterpreterShapes(assetInterpreter, expectedContract)) {
        debugPrint('ModelLifecycleManager: Loaded bundled classifier asset.');
        _swapInterpreter(textClassifierModelName, assetInterpreter);
        return ModelLoadResult(
          interpreter: assetInterpreter,
          source: ModelSource.bundledAsset,
          version: '1.0.0-classifier-asset',
          filePath: defaultClassifierAssetPath,
          isValidated: true,
        );
      } else {
        assetInterpreter.close();
      }
    } catch (_) {}

    // 3. Heuristic fallback
    return const ModelLoadResult(
      interpreter: null,
      source: ModelSource.fallbackHeuristics,
      version: 'fallback-heuristics',
      isValidated: false,
    );
  }

  /// Deploys a new TFLite binary and manifest entry safely to local storage.
  Future<bool> deployModelPackage({
    required String modelName,
    required List<int> tfliteBytes,
    required Map<String, dynamic> manifest,
  }) async {
    try {
      final activeDir = await getActiveModelDirectory();
      if (activeDir == null) return false;

      final fileName = modelName == ghostAiModelName ? 'ghost_ai.tflite' : '$modelName.tflite';
      final modelFile = File(p.join(activeDir.path, fileName));
      final manifestFile = File(p.join(activeDir.path, 'model_manifest.json'));

      await modelFile.writeAsBytes(tfliteBytes, flush: true);

      Map<String, dynamic> existingManifest = {};
      if (await manifestFile.exists()) {
        try {
          final content = await manifestFile.readAsString();
          existingManifest = jsonDecode(content) as Map<String, dynamic>;
        } catch (_) {}
      }

      existingManifest[modelName] = manifest;
      await manifestFile.writeAsString(jsonEncode(existingManifest), flush: true);

      debugPrint('ModelLifecycleManager: Deployed model package for $modelName successfully.');
      return true;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Failed to deploy model package $modelName: $e');
      return false;
    }
  }

  Future<ModelLoadResult?> _tryLoadFromFile(
    File file, {
    required ModelContract expectedContract,
    required String modelName,
  }) async {
    try {
      // Validate manifest contract if present
      final manifest = await loadManifest();
      if (manifest != null && manifest.containsKey(modelName)) {
        try {
          final contract = ModelContract.fromJson(manifest[modelName] as Map<String, dynamic>);
          if (!validateContract(contract, expectedContract)) {
            debugPrint('ModelLifecycleManager: Manifest contract validation failed for $modelName.');
            return null;
          }
        } catch (e) {
          debugPrint('ModelLifecycleManager: Error parsing contract from manifest: $e');
        }
      }

      final interpreter = Interpreter.fromFile(file);
      if (!_verifyInterpreterShapes(interpreter, expectedContract)) {
        debugPrint('ModelLifecycleManager: Interpreter shape mismatch for ${file.path}');
        interpreter.close();
        return null;
      }

      final mtime = await file.lastModified();
      final version = 'dynamic-${mtime.millisecondsSinceEpoch}';

      return ModelLoadResult(
        interpreter: interpreter,
        source: ModelSource.dynamicFile,
        version: version,
        filePath: file.path,
        isValidated: true,
      );
    } catch (e) {
      debugPrint('ModelLifecycleManager: Isolated exception while loading interpreter from ${file.path}: $e');
      return null;
    }
  }

  bool _verifyInterpreterShapes(Interpreter interpreter, ModelContract contract) {
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;

      final inputMatches = listEquals(inputShape, contract.inputShape);
      final outputMatches = listEquals(outputShape, contract.outputShape);

      return inputMatches && outputMatches;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error reading interpreter tensor shapes: $e');
      return false;
    }
  }

  void _swapInterpreter(String modelName, Interpreter? newInterpreter) {
    if (modelName == ghostAiModelName) {
      if (_activeGhostAiInterpreter != null && _activeGhostAiInterpreter != newInterpreter) {
        try {
          _activeGhostAiInterpreter!.close();
        } catch (_) {}
      }
      _activeGhostAiInterpreter = newInterpreter;
    } else if (modelName == textClassifierModelName) {
      if (_activeClassifierInterpreter != null && _activeClassifierInterpreter != newInterpreter) {
        try {
          _activeClassifierInterpreter!.close();
        } catch (_) {}
      }
      _activeClassifierInterpreter = newInterpreter;
    }
  }

  /// Closes active interpreters and resets state (used during app shutdown or tests).
  void disposeInterpreters() {
    try {
      _activeGhostAiInterpreter?.close();
    } catch (_) {}
    try {
      _activeClassifierInterpreter?.close();
    } catch (_) {}
    _activeGhostAiInterpreter = null;
    _activeClassifierInterpreter = null;
  }
}
