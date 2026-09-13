import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Active source origin for an ML model interpreter.
enum ModelSource {
  dynamicFile,
  bundledAsset,
  fallbackHeuristics,
}

/// Result of a model load request containing interpreter instance and metadata.
class ModelLoadResult {
  final Interpreter? interpreter;
  final ModelSource source;
  final String version;
  final String? filePath;
  final String? error;

  const ModelLoadResult({
    this.interpreter,
    required this.source,
    required this.version,
    this.filePath,
    this.error,
  });

  bool get isLoaded => interpreter != null;
}

/// Manages dynamic on-device model file inspection, shape validation,
/// loading, and graceful fallback to bundled assets or heuristics.
class ModelLifecycleManager {
  static const String ghostAiModelFileName = 'ghost_ai.tflite';
  static const String categoryClassifierModelFileName = 'litert_classifier.tflite';
  static const String defaultGhostAiAssetPath = 'assets/model.tflite';

  /// Dynamically inspects local device application documents storage for updated
  /// GhostAI look-again TFLite binaries before falling back to asset defaults.
  static Future<ModelLoadResult> loadGhostAiModel({
    String? customDirectoryPath,
    List<int> expectedInputShape = const [1, 63],
    List<int> expectedOutputShape = const [1, 1],
  }) async {
    // 1. Inspect dynamic local documents directory
    try {
      Directory? docDir;
      if (customDirectoryPath != null) {
        docDir = Directory(customDirectoryPath);
      } else {
        try {
          docDir = await getApplicationDocumentsDirectory();
        } catch (e) {
          debugPrint('ModelLifecycleManager: Could not resolve documents directory: $e');
        }
      }

      if (docDir != null && await docDir.exists()) {
        final candidateNames = [ghostAiModelFileName, 'model.tflite'];
        for (final fileName in candidateNames) {
          final dynamicFile = File(p.join(docDir.path, fileName));
          if (await dynamicFile.exists()) {
            final length = await dynamicFile.length();
            if (length > 0) {
              final result = await _tryLoadFromFile(
                dynamicFile,
                expectedInputShape: expectedInputShape,
                expectedOutputShape: expectedOutputShape,
              );
              if (result != null) {
                debugPrint('ModelLifecycleManager: Dynamic model loaded from ${dynamicFile.path}');
                return result;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Dynamic model inspection failed: $e');
    }

    // 2. Fallback to bundled asset model
    try {
      final assetInterpreter = await Interpreter.fromAsset(defaultGhostAiAssetPath);
      final inputTensor = assetInterpreter.getInputTensor(0);
      final outputTensor = assetInterpreter.getOutputTensor(0);

      if (_listEquals(inputTensor.shape, expectedInputShape) &&
          _listEquals(outputTensor.shape, expectedOutputShape)) {
        debugPrint('ModelLifecycleManager: Bundled asset model loaded.');
        return ModelLoadResult(
          interpreter: assetInterpreter,
          source: ModelSource.bundledAsset,
          version: '1.0.0-asset',
          filePath: defaultGhostAiAssetPath,
        );
      } else {
        debugPrint('ModelLifecycleManager: Asset model tensor shape mismatch: input ${inputTensor.shape}, output ${outputTensor.shape}');
        assetInterpreter.close();
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Bundled asset model failed to load: $e');
    }

    // 3. Fallback to heuristic execution engine
    return const ModelLoadResult(
      interpreter: null,
      source: ModelSource.fallbackHeuristics,
      version: 'fallback-heuristics',
    );
  }

  /// Inspects and loads category classification dynamic or asset model interpreters.
  static Future<ModelLoadResult> loadCategoryClassifierModel({
    String? customDirectoryPath,
    List<int> expectedInputShape = const [1, 64],
    List<int> expectedOutputShape = const [1, 5],
  }) async {
    try {
      Directory? docDir;
      if (customDirectoryPath != null) {
        docDir = Directory(customDirectoryPath);
      } else {
        try {
          docDir = await getApplicationDocumentsDirectory();
        } catch (_) {}
      }

      if (docDir != null && await docDir.exists()) {
        final dynamicFile = File(p.join(docDir.path, categoryClassifierModelFileName));
        if (await dynamicFile.exists() && await dynamicFile.length() > 0) {
          final result = await _tryLoadFromFile(
            dynamicFile,
            expectedInputShape: expectedInputShape,
            expectedOutputShape: expectedOutputShape,
          );
          if (result != null) {
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Category classifier dynamic model check failed: $e');
    }

    return const ModelLoadResult(
      interpreter: null,
      source: ModelSource.fallbackHeuristics,
      version: 'fallback-heuristics',
    );
  }

  static Future<ModelLoadResult?> _tryLoadFromFile(
    File file, {
    required List<int> expectedInputShape,
    required List<int> expectedOutputShape,
  }) async {
    try {
      final interpreter = Interpreter.fromFile(file);
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);

      if (!_listEquals(inputTensor.shape, expectedInputShape) ||
          !_listEquals(outputTensor.shape, expectedOutputShape)) {
        debugPrint('ModelLifecycleManager: Invalid shape in ${file.path}. Expected input $expectedInputShape, output $expectedOutputShape. Found input ${inputTensor.shape}, output ${outputTensor.shape}');
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
      );
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error instantiating interpreter from ${file.path}: $e');
      return null;
    }
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
