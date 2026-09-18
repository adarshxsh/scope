import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Represents standardized model metadata specification for release packaging.
class ModelManifest {
  final String modelName;
  final String version;
  final String schemaVersion;
  final int featureVectorSize;
  final String sha256;
  final List<int> inputShape;
  final List<int> outputShape;
  final Map<String, String>? artifacts;
  final String? createdAt;

  const ModelManifest({
    required this.modelName,
    required this.version,
    required this.schemaVersion,
    required this.featureVectorSize,
    required this.sha256,
    required this.inputShape,
    required this.outputShape,
    this.artifacts,
    this.createdAt,
  });

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    return ModelManifest(
      modelName: json['model_name'] as String? ?? 'unknown',
      version: json['version'] as String? ?? '1.0.0',
      schemaVersion: json['schema_version'] as String? ?? '1.0.0',
      featureVectorSize: json['feature_vector_size'] as int? ?? (json['input_shape'] != null ? (json['input_shape'] as List).last as int : 63),
      sha256: json['sha256'] as String? ?? '',
      inputShape: (json['input_shape'] as List?)?.map((e) => e as int).toList() ?? [1, 63],
      outputShape: (json['output_shape'] as List?)?.map((e) => e as int).toList() ?? [1, 1],
      artifacts: (json['artifacts'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model_name': modelName,
      'version': version,
      'schema_version': schemaVersion,
      'feature_vector_size': featureVectorSize,
      'sha256': sha256,
      'input_shape': inputShape,
      'output_shape': outputShape,
      if (artifacts != null) 'artifacts': artifacts,
      if (createdAt != null) 'created_at': createdAt,
    };
  }
}

/// Dynamic Model Lifecycle Manager managing TFLite binaries in local storage,
/// verifying SHA256 checksums & schema dimensions, and facilitating hot-swaps.
class ModelLifecycleManager {
  static ModelLifecycleManager? _instance;
  Directory? _storageDir;
  
  // Stream controller to notify components when a model is updated
  final StreamController<String> _modelUpdateController = StreamController<String>.broadcast();

  // Active interpreter cache
  final Map<String, Interpreter> _activeInterpreters = {};
  final Map<String, ModelManifest> _activeManifests = {};

  ModelLifecycleManager._();

  static ModelLifecycleManager get instance => _instance ??= ModelLifecycleManager._();

  Stream<String> get onModelUpdated => _modelUpdateController.stream;

  /// Override storage directory (primarily for testing)
  void setStorageDirectory(Directory dir) {
    _storageDir = dir;
  }

  /// Get local app storage directory for models
  Future<Directory> _getStorageDirectory() async {
    if (_storageDir != null) return _storageDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory(p.join(appDir.path, 'models'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    _storageDir = modelDir;
    return modelDir;
  }

  /// Validates a binary against manifest SHA256 hash
  bool verifyChecksum(Uint8List modelBytes, String expectedSha256) {
    if (expectedSha256.isEmpty) return false;
    final digest = sha256.convert(modelBytes);
    return digest.toString().toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Validates input shape/dimensions against expected schema requirements
  bool verifySchemaDimensions(ModelManifest manifest, {int? expectedInputDim, List<int>? expectedInputShape}) {
    if (expectedInputDim != null) {
      if (manifest.featureVectorSize != expectedInputDim) {
        debugPrint('Schema check failed: featureVectorSize ${manifest.featureVectorSize} != $expectedInputDim');
        return false;
      }
      if (manifest.inputShape.isNotEmpty && manifest.inputShape.last != expectedInputDim) {
        debugPrint('Schema check failed: inputShape ${manifest.inputShape} last dim != $expectedInputDim');
        return false;
      }
    }
    if (expectedInputShape != null) {
      if (manifest.inputShape.length != expectedInputShape.length) {
        return false;
      }
      for (int i = 0; i < expectedInputShape.length; i++) {
        if (expectedInputShape[i] != -1 && manifest.inputShape[i] != expectedInputShape[i]) {
          return false;
        }
      }
    }
    return true;
  }

  /// Validates full manifest and model binary bytes
  bool validateModelBundle(ModelManifest manifest, Uint8List modelBytes, {int? expectedInputDim}) {
    if (!verifyChecksum(modelBytes, manifest.sha256)) {
      debugPrint('ModelLifecycleManager: SHA256 mismatch for model ${manifest.modelName}');
      return false;
    }
    if (!verifySchemaDimensions(manifest, expectedInputDim: expectedInputDim)) {
      debugPrint('ModelLifecycleManager: Schema dimension mismatch for model ${manifest.modelName}');
      return false;
    }
    return true;
  }

  /// Registers/updates a model package on local storage after strict verification
  Future<bool> registerModelPackage({
    required String manifestJsonStr,
    required Uint8List modelBytes,
    String? vocabContent,
    int? expectedInputDim,
  }) async {
    try {
      final jsonMap = json.decode(manifestJsonStr) as Map<String, dynamic>;
      final manifest = ModelManifest.fromJson(jsonMap);

      if (!validateModelBundle(manifest, modelBytes, expectedInputDim: expectedInputDim)) {
        return false;
      }

      final baseDir = await _getStorageDirectory();
      final targetDir = Directory(p.join(baseDir.path, manifest.modelName));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // Write manifest.json
      final manifestFile = File(p.join(targetDir.path, 'manifest.json'));
      await manifestFile.writeAsString(manifestJsonStr);

      // Write binary .tflite file
      final binaryFileName = manifest.artifacts?['tflite'] ?? '${manifest.modelName}.tflite';
      final binaryFile = File(p.join(targetDir.path, binaryFileName));
      await binaryFile.writeAsBytes(modelBytes);

      // Write vocab.txt if provided
      if (vocabContent != null) {
        final vocabFileName = manifest.artifacts?['vocab'] ?? 'vocab.txt';
        final vocabFile = File(p.join(targetDir.path, vocabFileName));
        await vocabFile.writeAsString(vocabContent);
      }

      // Load new interpreter non-blockingly
      final newInterpreter = Interpreter.fromBuffer(modelBytes);
      
      // Thread-safe reference update
      final oldInterpreter = _activeInterpreters[manifest.modelName];
      _activeInterpreters[manifest.modelName] = newInterpreter;
      _activeManifests[manifest.modelName] = manifest;

      // Close old interpreter safely
      oldInterpreter?.close();

      // Notify listeners
      _modelUpdateController.add(manifest.modelName);
      debugPrint('ModelLifecycleManager: Successfully registered and hot-swapped model "${manifest.modelName}" (v${manifest.version})');
      return true;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Failed to register model package: $e');
      return false;
    }
  }

  /// Load or retrieve active interpreter for modelName (local storage or fallback to asset)
  Future<Interpreter?> getInterpreter(String modelName, {String? assetFallbackPath, int? expectedInputDim}) async {
    // Return cached interpreter if valid
    if (_activeInterpreters.containsKey(modelName)) {
      return _activeInterpreters[modelName];
    }

    try {
      final baseDir = await _getStorageDirectory();
      final targetDir = Directory(p.join(baseDir.path, modelName));
      final manifestFile = File(p.join(targetDir.path, 'manifest.json'));

      if (await manifestFile.exists()) {
        final manifestJsonStr = await manifestFile.readAsString();
        final manifest = ModelManifest.fromJson(json.decode(manifestJsonStr));
        final binaryFileName = manifest.artifacts?['tflite'] ?? '$modelName.tflite';
        final binaryFile = File(p.join(targetDir.path, binaryFileName));

        if (await binaryFile.exists()) {
          final bytes = await binaryFile.readAsBytes();
          if (validateModelBundle(manifest, bytes, expectedInputDim: expectedInputDim)) {
            final interpreter = Interpreter.fromBuffer(bytes);
            _activeInterpreters[modelName] = interpreter;
            _activeManifests[modelName] = manifest;
            return interpreter;
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error loading local model $modelName: $e');
    }

    // Asset fallback
    if (assetFallbackPath != null) {
      try {
        final interpreter = await Interpreter.fromAsset(assetFallbackPath);
        _activeInterpreters[modelName] = interpreter;
        debugPrint('ModelLifecycleManager: Loaded asset fallback model from $assetFallbackPath');
        return interpreter;
      } catch (e) {
        debugPrint('ModelLifecycleManager: Failed to load asset fallback $assetFallbackPath: $e');
      }
    }

    return null;
  }

  /// Get active model manifest if loaded
  ModelManifest? getManifest(String modelName) {
    return _activeManifests[modelName];
  }

  /// Clean up resources
  void dispose() {
    for (final interpreter in _activeInterpreters.values) {
      interpreter.close();
    }
    _activeInterpreters.clear();
    _activeManifests.clear();
  }
}
