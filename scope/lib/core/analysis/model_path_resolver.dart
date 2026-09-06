import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Indicates the source from which the ML model was loaded.
enum ModelSource {
  local,
  asset,
  none,
}

/// Represents the result of an interpreter loading attempt.
class ModelLoadResult {
  final Interpreter? interpreter;
  final ModelSource source;
  final String? filePath;
  final String? errorMessage;

  bool get isLoaded => interpreter != null;
  bool get isLocal => source == ModelSource.local;
  bool get isAsset => source == ModelSource.asset;

  const ModelLoadResult({
    this.interpreter,
    required this.source,
    this.filePath,
    this.errorMessage,
  });
}

/// Resolves and loads the ML model file during application launch initialization.
/// Inspects persistent local storage first, falling back to bundled assets
/// if no updated model file is present or if reading fails.
class ModelPathResolver {
  final String localFileName;
  final String assetPath;
  final Directory? customStorageDir;

  ModelPathResolver({
    this.localFileName = 'updated_model.tflite',
    this.assetPath = 'assets/model.tflite',
    this.customStorageDir,
  });

  /// Returns the persistent local application storage directory.
  Future<Directory?> getLocalDirectory() async {
    if (customStorageDir != null) return customStorageDir;
    try {
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      debugPrint('ModelPathResolver: Could not access application documents directory: $e');
      return null;
    }
  }

  /// Inspects persistent local application storage for an updated model file.
  /// Checks candidate file paths in order of preference:
  /// 1. `updated_model.tflite`
  /// 2. `model.tflite`
  /// 3. `models/model.tflite`
  Future<File?> getLocalModelFile() async {
    final dir = await getLocalDirectory();
    if (dir == null) return null;

    final candidatePaths = [
      '${dir.path}/$localFileName',
      '${dir.path}/model.tflite',
      '${dir.path}/models/model.tflite',
    ];

    for (final path in candidatePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final length = await file.length();
          if (length > 0) {
            debugPrint('ModelPathResolver: Found non-empty local model file at $path ($length bytes).');
            return file;
          } else {
            debugPrint('ModelPathResolver: Found empty local model file at $path, skipping.');
          }
        }
      } catch (e) {
        debugPrint('ModelPathResolver: Error checking local model file at $path: $e');
      }
    }
    return null;
  }

  /// Resolves the model path and loads the TFLite Interpreter.
  /// First checks persistent local application storage for updated model files.
  /// If a valid local model file exists, loads it via [Interpreter.fromFile].
  /// If no local model exists or reading/loading fails, automatically falls back
  /// to the default bundled asset model via [Interpreter.fromAsset].
  Future<ModelLoadResult> resolveAndLoad() async {
    // 1. Check local persistent application storage for updated model file
    final localFile = await getLocalModelFile();

    if (localFile != null) {
      try {
        debugPrint('ModelPathResolver: Attempting to load updated model from persistent storage (${localFile.path})...');
        final interpreter = Interpreter.fromFile(localFile);
        debugPrint('ModelPathResolver: Successfully loaded model from local storage (${localFile.path}).');
        return ModelLoadResult(
          interpreter: interpreter,
          source: ModelSource.local,
          filePath: localFile.path,
        );
      } catch (e) {
        debugPrint('ModelPathResolver: Failed to load model from local storage file (${localFile.path}): $e. Falling back to bundled asset model.');
      }
    } else {
      debugPrint('ModelPathResolver: No updated local model file found in persistent storage.');
    }

    // 2. Fallback: Load default bundled asset model
    try {
      debugPrint('ModelPathResolver: Attempting to load default bundled model from asset ($assetPath)...');
      final interpreter = await Interpreter.fromAsset(assetPath);
      debugPrint('ModelPathResolver: Successfully loaded default bundled asset model ($assetPath).');
      return ModelLoadResult(
        interpreter: interpreter,
        source: ModelSource.asset,
        filePath: assetPath,
      );
    } catch (e) {
      debugPrint('ModelPathResolver: Failed to load bundled asset model ($assetPath): $e');
      return ModelLoadResult(
        interpreter: null,
        source: ModelSource.none,
        errorMessage: e.toString(),
      );
    }
  }
}
