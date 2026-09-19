import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Contract configuration for expected model tensor shapes and versions.
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
}

/// Dynamic Model Registry and Manager handling local TFLite binaries,
/// contract validation, and asset fallbacks.
class ModelLifecycleManager {
  static ModelLifecycleManager? _instance;
  static ModelLifecycleManager get instance => _instance ??= ModelLifecycleManager._();

  ModelLifecycleManager._();

  static const String ghostAiModelName = 'ghost_ai';
  static const String textClassifierModelName = 'text_classifier';

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
    // 1. Try local active directory
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

    // 2. Fall back to asset manifest
    try {
      final content = await rootBundle.loadString('assets/model_manifest.json');
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Failed to load asset model_manifest.json: $e');
      return null;
    }
  }

  /// Validates a model contract against expected specification.
  bool validateContract(ModelContract contract, ModelContract expected) {
    if (contract.featureVersion != expected.featureVersion) {
      debugPrint('ModelLifecycleManager contract error: feature_version mismatch '
          '(${contract.featureVersion} vs expected ${expected.featureVersion})');
      return false;
    }

    if (!_listEquals(contract.inputShape, expected.inputShape)) {
      debugPrint('ModelLifecycleManager contract error: input_shape mismatch '
          '(${contract.inputShape} vs expected ${expected.inputShape})');
      return false;
    }

    if (!_listEquals(contract.outputShape, expected.outputShape)) {
      debugPrint('ModelLifecycleManager contract error: output_shape mismatch '
          '(${contract.outputShape} vs expected ${expected.outputShape})');
      return false;
    }

    return true;
  }

  /// Loads GhostAI look-again score interpreter dynamically.
  Future<Interpreter?> loadGhostAiInterpreter() async {
    return _loadInterpreter(
      modelFileName: 'ghost_ai.tflite',
      modelName: ghostAiModelName,
      expectedContract: defaultGhostAiContract,
      assetFallbackPath: 'assets/model.tflite',
    );
  }

  /// Loads Text Classifier interpreter dynamically.
  Future<Interpreter?> loadTextClassifierInterpreter() async {
    return _loadInterpreter(
      modelFileName: 'text_classifier.tflite',
      modelName: textClassifierModelName,
      expectedContract: defaultTextClassifierContract,
      assetFallbackPath: 'assets/text_classifier.tflite',
    );
  }

  /// Deploy a new model package (binary + manifest) to local active storage.
  Future<bool> deployModelPackage({
    required String modelName,
    required List<int> tfliteBytes,
    required Map<String, dynamic> manifest,
  }) async {
    final activeDir = await getActiveModelDirectory();
    if (activeDir == null) return false;

    final fileName = modelName == ghostAiModelName ? 'ghost_ai.tflite' : '$modelName.tflite';
    final modelFile = File(p.join(activeDir.path, fileName));
    final manifestFile = File(p.join(activeDir.path, 'model_manifest.json'));

    try {
      await modelFile.writeAsBytes(tfliteBytes, flush: true);

      Map<String, dynamic> existingManifest = {};
      if (manifestFile.existsSync()) {
        try {
          existingManifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }

      existingManifest[modelName] = manifest;
      await manifestFile.writeAsString(jsonEncode(existingManifest), flush: true);

      debugPrint('ModelLifecycleManager: Deployed model package $modelName successfully.');
      return true;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Failed to deploy model package $modelName: $e');
      return false;
    }
  }

  Future<Interpreter?> _loadInterpreter({
    required String modelFileName,
    required String modelName,
    required ModelContract expectedContract,
    required String assetFallbackPath,
  }) async {
    // 1. Check local storage
    final activeDir = await getActiveModelDirectory();
    if (activeDir != null) {
      final localFile = File(p.join(activeDir.path, modelFileName));
      if (localFile.existsSync()) {
        // Validate local manifest contract first
        final manifest = await loadManifest();
        if (manifest != null && manifest.containsKey(modelName)) {
          final contract = ModelContract.fromJson(manifest[modelName] as Map<String, dynamic>);
          if (!validateContract(contract, expectedContract)) {
            debugPrint('ModelLifecycleManager: Local model manifest validation failed for $modelName.');
            return _loadAssetFallback(assetFallbackPath, modelName);
          }
        }

        try {
          final interpreter = Interpreter.fromFile(localFile);
          if (_verifyInterpreterShapes(interpreter, expectedContract)) {
            debugPrint('ModelLifecycleManager: Loaded dynamic local model for $modelName from ${localFile.path}');
            return interpreter;
          } else {
            interpreter.close();
            debugPrint('ModelLifecycleManager: Local interpreter tensor shape mismatch for $modelName.');
          }
        } catch (e) {
          debugPrint('ModelLifecycleManager: Failed to load local TFLite binary for $modelName: $e');
        }
      }
    }

    // 2. Asset fallback
    return _loadAssetFallback(assetFallbackPath, modelName);
  }

  Future<Interpreter?> _loadAssetFallback(String assetPath, String modelName) async {
    try {
      final interpreter = await Interpreter.fromAsset(assetPath);
      debugPrint('ModelLifecycleManager: Loaded default asset fallback for $modelName ($assetPath)');
      return interpreter;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Default asset fallback unavailable for $modelName ($assetPath): $e');
      return null;
    }
  }

  bool _verifyInterpreterShapes(Interpreter interpreter, ModelContract contract) {
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;

      final inputMatches = _listEquals(inputShape, contract.inputShape);
      final outputMatches = _listEquals(outputShape, contract.outputShape);

      return inputMatches && outputMatches;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error reading tensor shapes: $e');
      return false;
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
