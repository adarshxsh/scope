import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Represents the source of the currently loaded TFLite model.
enum ModelSource {
  /// Loaded dynamically from local device storage (OTA update).
  dynamic,

  /// Loaded from the static application asset bundle.
  asset,

  /// Model unavailable or failed to load; using rule/heuristic fallback.
  fallback,
}

/// Result metadata for dynamic model update operations.
class ModelUpdateResult {
  final bool success;
  final String message;
  final ModelSource source;
  final String? version;

  const ModelUpdateResult({
    required this.success,
    required this.message,
    required this.source,
    this.version,
  });

  @override
  String toString() => 'ModelUpdateResult(success: $success, source: $source, message: $message)';
}

/// Abstraction managing dynamic TFLite ML model lookup, validation, atomic updates,
/// safe fallback to static bundle assets, and native memory lifecycle cleanup.
class ModelManager {
  Interpreter? _interpreter;
  ModelSource _modelSource = ModelSource.fallback;
  String _modelVersion = 'fallback-heuristics';
  String? _modelPath;
  String? _customBaseDir;

  ModelManager({String? customBaseDir}) : _customBaseDir = customBaseDir;

  /// Returns the active interpreter instance or null if in fallback mode.
  Interpreter? get interpreter => _interpreter;

  /// Returns whether a valid model interpreter is currently loaded.
  bool get isModelLoaded => _interpreter != null;

  /// Returns the current model source (dynamic, asset, or fallback).
  ModelSource get modelSource => _modelSource;

  /// Returns whether the model was loaded from dynamic local storage.
  bool get isDynamicModel => _modelSource == ModelSource.dynamic;

  /// Returns the model version string.
  String get modelVersion => _modelVersion;

  /// Returns the path/asset identifier of the loaded model.
  String? get modelPath => _modelPath;

  /// Resolves the directory for dynamic model storage with sanitization and fallback.
  Future<Directory> getModelDirectory() async {
    if (_customBaseDir != null && _customBaseDir!.isNotEmpty) {
      final dir = Directory(_customBaseDir!);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(appDir.path, 'models'));
      if (!modelsDir.existsSync()) {
        modelsDir.createSync(recursive: true);
      }
      return modelsDir;
    } catch (e) {
      // Fallback for environments where path_provider is unavailable (e.g., unit tests)
      final tempDir = Directory(p.join(Directory.systemTemp.path, 'scope_models'));
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      return tempDir;
    }
  }

  /// Sanitizes and verifies that [filePath] is strictly inside [targetDir].
  /// Prevents directory traversal attacks.
  bool _isPathSafe(String filePath, Directory targetDir) {
    try {
      final canonicalTarget = targetDir.absolute.path;
      final canonicalFile = File(filePath).absolute.path;
      return canonicalFile.startsWith(canonicalTarget);
    } catch (_) {
      return false;
    }
  }

  /// Loads the TFLite interpreter by checking local dynamic storage first,
  /// falling back to static asset bundle, and then heuristic fallback.
  Future<Interpreter?> loadInterpreter({
    String assetPath = 'assets/model.tflite',
    String modelName = 'ghost_ai.tflite',
  }) async {
    // Safely close old interpreter before loading to avoid native memory leak
    _closeInterpreter();

    // 1. Check for dynamic model file in local storage
    try {
      final dir = await getModelDirectory();
      final dynamicFile = File(p.join(dir.path, modelName));

      if (_isPathSafe(dynamicFile.path, dir) &&
          dynamicFile.existsSync() &&
          dynamicFile.lengthSync() > 100) {
        try {
          final dynamicInterpreter = await Interpreter.fromFile(dynamicFile);
          _interpreter = dynamicInterpreter;
          _modelSource = ModelSource.dynamic;
          _modelVersion = '1.0.0-tflite-dynamic';
          _modelPath = dynamicFile.path;
          debugPrint('ModelManager: Dynamic TFLite model loaded successfully from ${_modelPath}.');
          return _interpreter;
        } catch (e) {
          debugPrint('ModelManager: Dynamic model file exists but failed to load ($e). Falling back to asset.');
        }
      }
    } catch (e) {
      debugPrint('ModelManager: Error inspecting dynamic model storage: $e');
    }

    // 2. Fallback: Load static model asset from application bundle
    try {
      final assetInterpreter = await Interpreter.fromAsset(assetPath);
      _interpreter = assetInterpreter;
      _modelSource = ModelSource.asset;
      _modelVersion = '1.0.0-tflite';
      _modelPath = assetPath;
      debugPrint('ModelManager: Static asset model loaded successfully from $assetPath.');
      return _interpreter;
    } catch (e) {
      debugPrint('ModelManager: Failed to load static asset model ($assetPath): $e');
    }

    // 3. Fallback: Model uninitializable, proceed with heuristic fallback
    _interpreter = null;
    _modelSource = ModelSource.fallback;
    _modelVersion = 'fallback-heuristics';
    _modelPath = null;
    debugPrint('ModelManager: Operating in heuristic fallback mode.');
    return null;
  }

  /// Updates the dynamic model from a local file with validation and atomic storage.
  Future<ModelUpdateResult> updateModelFromFile(
    File sourceFile, {
    String modelName = 'ghost_ai.tflite',
    String version = '1.0.0-tflite-dynamic',
  }) async {
    if (!sourceFile.existsSync()) {
      return const ModelUpdateResult(
        success: false,
        message: 'Source model file does not exist.',
        source: ModelSource.fallback,
      );
    }

    final bytes = await sourceFile.readAsBytes();
    return updateModelFromBytes(bytes, modelName: modelName, version: version);
  }

  /// Updates the dynamic model from raw byte content with validation and atomic storage.
  Future<ModelUpdateResult> updateModelFromBytes(
    Uint8List bytes, {
    String modelName = 'ghost_ai.tflite',
    String version = '1.0.0-tflite-dynamic',
  }) async {
    // 1. Validation boundary checks
    if (bytes.length < 100) {
      return const ModelUpdateResult(
        success: false,
        message: 'Invalid model file: file size too small (must be > 100 bytes).',
        source: ModelSource.fallback,
      );
    }

    try {
      final dir = await getModelDirectory();
      final targetPath = p.join(dir.path, modelName);
      final tempPath = p.join(dir.path, '$modelName.tmp');

      if (!_isPathSafe(targetPath, dir)) {
        return const ModelUpdateResult(
          success: false,
          message: 'Security validation failed: path traversal detected.',
          source: ModelSource.fallback,
        );
      }

      // 2. Atomic write operation using temporary file
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes, flush: true);

      final targetFile = File(targetPath);
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      tempFile.renameSync(targetPath);

      // 3. Verify and load updated interpreter
      _closeInterpreter();
      try {
        final newInterpreter = await Interpreter.fromFile(File(targetPath));
        _interpreter = newInterpreter;
        _modelSource = ModelSource.dynamic;
        _modelVersion = version;
        _modelPath = targetPath;
        debugPrint('ModelManager: Successfully updated and loaded dynamic model.');

        return ModelUpdateResult(
          success: true,
          message: 'Dynamic ML model updated successfully.',
          source: ModelSource.dynamic,
          version: _modelVersion,
        );
      } catch (e) {
        // Quarantine / remove corrupted target file
        final invalidFile = File(targetPath);
        if (invalidFile.existsSync()) {
          invalidFile.deleteSync();
        }
        // Fallback to static asset
        await loadInterpreter();

        return ModelUpdateResult(
          success: false,
          message: 'Updated model verification failed ($e). Reverted to fallback model.',
          source: _modelSource,
          version: _modelVersion,
        );
      }
    } catch (e) {
      return ModelUpdateResult(
        success: false,
        message: 'Failed to write dynamic model: $e',
        source: _modelSource,
        version: _modelVersion,
      );
    }
  }

  /// Resets the dynamic model override and reverts to static bundle asset.
  Future<void> resetToAssetModel({
    String assetPath = 'assets/model.tflite',
    String modelName = 'ghost_ai.tflite',
  }) async {
    try {
      final dir = await getModelDirectory();
      final dynamicFile = File(p.join(dir.path, modelName));
      if (dynamicFile.existsSync()) {
        dynamicFile.deleteSync();
      }
    } catch (e) {
      debugPrint('ModelManager: Failed to delete dynamic model file: $e');
    }

    _closeInterpreter();
    await loadInterpreter(assetPath: assetPath, modelName: modelName);
  }

  /// Safely closes the active TFLite interpreter to prevent native memory leaks.
  void _closeInterpreter() {
    if (_interpreter != null) {
      try {
        _interpreter!.close();
      } catch (e) {
        debugPrint('ModelManager: Exception closing interpreter: $e');
      }
      _interpreter = null;
    }
  }

  /// Disposes resources managed by [ModelManager].
  void dispose() {
    _closeInterpreter();
    _modelSource = ModelSource.fallback;
    _modelVersion = 'fallback-heuristics';
    _modelPath = null;
  }
}
