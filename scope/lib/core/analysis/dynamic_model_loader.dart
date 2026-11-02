import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Supported types of ML model assets.
enum ModelAssetType {
  tflite,
  rules,
  vocab,
  manifest,
}

/// The origin source of loaded model assets.
enum ModelSourceType {
  dynamic,
  staticAsset,
  fallbackHeuristic,
}

/// Represents an audit log event for ML model lifecycle and updates.
class ModelAuditLog {
  final DateTime timestamp;
  final String eventType; // e.g. LOAD_DYNAMIC, LOAD_STATIC_FALLBACK, UPDATE_SUCCESS, VALIDATION_FAILED, CLEAR_UPDATES
  final String assetType; // e.g. tflite, rules, vocab, all
  final String source; // e.g. path or asset string
  final String version;
  final String status; // success, failure, warning
  final String details;

  ModelAuditLog({
    DateTime? timestamp,
    required this.eventType,
    required this.assetType,
    required this.source,
    required this.version,
    required this.status,
    required this.details,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'eventType': eventType,
        'assetType': assetType,
        'source': source,
        'version': version,
        'status': status,
        'details': details,
      };

  factory ModelAuditLog.fromMap(Map<String, dynamic> map) => ModelAuditLog(
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
        eventType: map['eventType'] as String? ?? 'UNKNOWN',
        assetType: map['assetType'] as String? ?? 'unknown',
        source: map['source'] as String? ?? '',
        version: map['version'] as String? ?? '0.0.0',
        status: map['status'] as String? ?? 'info',
        details: map['details'] as String? ?? '',
      );

  @override
  String toString() =>
      '[$timestamp] [$status] $eventType ($assetType) v$version - $details (source: $source)';
}

/// Outcome of asset validation checks.
class ModelValidationResult {
  final bool isValid;
  final String? errorMessage;
  final int fileLength;
  final Map<String, dynamic> metadata;

  const ModelValidationResult({
    required this.isValid,
    this.errorMessage,
    this.fileLength = 0,
    this.metadata = const {},
  });

  factory ModelValidationResult.valid({
    int fileLength = 0,
    Map<String, dynamic> metadata = const {},
  }) =>
      ModelValidationResult(
        isValid: true,
        fileLength: fileLength,
        metadata: metadata,
      );

  factory ModelValidationResult.invalid(String errorMessage, {int fileLength = 0}) =>
      ModelValidationResult(
        isValid: false,
        errorMessage: errorMessage,
        fileLength: fileLength,
      );
}

/// Central manager and loader for dynamic ML model assets with validation, fallback, and audit logging.
class DynamicModelLoader {
  static DynamicModelLoader? _instance;

  final List<ModelAuditLog> _auditLogs = [];
  Directory? _customUpdatesDirectory;

  // Track sources of currently loaded assets
  ModelSourceType _tfliteSource = ModelSourceType.fallbackHeuristic;
  ModelSourceType _rulesSource = ModelSourceType.fallbackHeuristic;
  ModelSourceType _vocabSource = ModelSourceType.fallbackHeuristic;

  String _currentVersion = '1.0.0-bundled';

  DynamicModelLoader._();

  static DynamicModelLoader get instance => _instance ??= DynamicModelLoader._();

  /// Allows overriding updates directory (primarily for testing).
  void setUpdatesDirectory(Directory dir) {
    _customUpdatesDirectory = dir;
  }

  /// Returns the dynamic ML updates directory path.
  Future<Directory> getUpdatesDirectory() async {
    if (_customUpdatesDirectory != null) {
      if (!await _customUpdatesDirectory!.exists()) {
        await _customUpdatesDirectory!.create(recursive: true);
      }
      return _customUpdatesDirectory!;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final updatesDir = Directory('${appDir.path}/ml_updates');
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }
      return updatesDir;
    } catch (e) {
      // Fallback if path provider fails (e.g., unit test without channel)
      final tempDir = Directory('${Directory.systemTemp.path}/scope_ml_updates');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      return tempDir;
    }
  }

  /// Returns immutable copy of recorded audit logs.
  List<ModelAuditLog> getAuditLogs() => List.unmodifiable(_auditLogs);

  /// Clears in-memory audit logs.
  void clearAuditLogs() {
    _auditLogs.clear();
  }

  ModelSourceType getLoadedSource(ModelAssetType type) {
    switch (type) {
      case ModelAssetType.tflite:
        return _tfliteSource;
      case ModelAssetType.rules:
        return _rulesSource;
      case ModelAssetType.vocab:
        return _vocabSource;
      case ModelAssetType.manifest:
        return ModelSourceType.staticAsset;
    }
  }

  String get currentVersion => _currentVersion;

  void _addAuditLog({
    required String eventType,
    required String assetType,
    required String source,
    required String version,
    required String status,
    required String details,
  }) {
    final log = ModelAuditLog(
      eventType: eventType,
      assetType: assetType,
      source: source,
      version: version,
      status: status,
      details: details,
    );
    _auditLogs.add(log);
    if (kDebugMode) {
      debugPrint('DynamicModelLoader: $log');
    }
  }

  // --- Validation Methods ---

  /// Validates a TFLite model byte buffer.
  ModelValidationResult validateTfliteBuffer(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return ModelValidationResult.invalid('TFLite buffer is null or empty');
    }
    // Basic threshold size check for TFLite models
    if (bytes.length < 100) {
      return ModelValidationResult.invalid(
          'TFLite buffer size (${bytes.length} bytes) is below minimum threshold (100 bytes)',
          fileLength: bytes.length);
    }
    return ModelValidationResult.valid(fileLength: bytes.length);
  }

  /// Validates a Rules JSON string format and schema.
  ModelValidationResult validateRulesJson(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return ModelValidationResult.invalid('Rules JSON string is null or empty');
    }
    try {
      final map = json.decode(jsonStr);
      if (map is! Map<String, dynamic>) {
        return ModelValidationResult.invalid('Rules JSON root must be a JSON object');
      }
      if (!map.containsKey('rules') || map['rules'] is! List) {
        return ModelValidationResult.invalid('Rules JSON missing valid "rules" array field');
      }
      final version = map['version'] as String? ?? '0.0.0';
      return ModelValidationResult.valid(
        fileLength: jsonStr.length,
        metadata: {'version': version, 'ruleCount': (map['rules'] as List).length},
      );
    } catch (e) {
      return ModelValidationResult.invalid('Invalid JSON syntax: $e', fileLength: jsonStr.length);
    }
  }

  /// Validates a Vocab text file.
  ModelValidationResult validateVocabString(String? vocabStr) {
    if (vocabStr == null || vocabStr.trim().isEmpty) {
      return ModelValidationResult.invalid('Vocab string is null or empty');
    }
    final lines = vocabStr.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return ModelValidationResult.invalid('Vocab string contains no valid token entries');
    }
    return ModelValidationResult.valid(
      fileLength: vocabStr.length,
      metadata: {'tokenCount': lines.length},
    );
  }

  // --- Loader Methods ---

  /// Loads TFLite model bytes, prioritizing dynamic update directory with fallback to static asset.
  Future<Uint8List?> loadTfliteBuffer({String assetPath = 'assets/model.tflite'}) async {
    // 1. Try dynamic file first
    try {
      final updatesDir = await getUpdatesDirectory();
      final dynamicFile = File('${updatesDir.path}/model.tflite');
      if (await dynamicFile.exists()) {
        final bytes = await dynamicFile.readAsBytes();
        final val = validateTfliteBuffer(bytes);
        if (val.isValid) {
          _tfliteSource = ModelSourceType.dynamic;
          _addAuditLog(
            eventType: 'LOAD_DYNAMIC',
            assetType: 'tflite',
            source: dynamicFile.path,
            version: _currentVersion,
            status: 'success',
            details: 'Loaded dynamic TFLite model (${bytes.length} bytes)',
          );
          return bytes;
        } else {
          _addAuditLog(
            eventType: 'VALIDATION_FAILED',
            assetType: 'tflite',
            source: dynamicFile.path,
            version: _currentVersion,
            status: 'warning',
            details: 'Dynamic TFLite validation failed: ${val.errorMessage}',
          );
        }
      }
    } catch (e) {
      _addAuditLog(
        eventType: 'LOAD_ERROR',
        assetType: 'tflite',
        source: 'dynamic_updates',
        version: _currentVersion,
        status: 'warning',
        details: 'Error accessing dynamic TFLite file: $e',
      );
    }

    // 2. Fallback to static asset bundle
    try {
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();
      final val = validateTfliteBuffer(bytes);
      if (val.isValid) {
        _tfliteSource = ModelSourceType.staticAsset;
        _addAuditLog(
          eventType: 'LOAD_STATIC_FALLBACK',
          assetType: 'tflite',
          source: assetPath,
          version: '1.0.0-bundled',
          status: 'success',
          details: 'Loaded bundled static asset TFLite model (${bytes.length} bytes)',
        );
        return bytes;
      }
    } catch (e) {
      _addAuditLog(
        eventType: 'LOAD_ERROR',
        assetType: 'tflite',
        source: assetPath,
        version: '1.0.0-bundled',
        status: 'failure',
        details: 'Failed to load static bundle asset: $e',
      );
    }

    // 3. Fallback to heuristic mode
    _tfliteSource = ModelSourceType.fallbackHeuristic;
    _addAuditLog(
      eventType: 'LOAD_HEURISTIC_FALLBACK',
      assetType: 'tflite',
      source: 'none',
      version: 'heuristic',
      status: 'warning',
      details: 'Operating in heuristic fallback mode',
    );
    return null;
  }

  /// Loads Rules JSON string, prioritizing dynamic update directory with fallback to static asset.
  Future<String?> loadRulesJson({String assetPath = 'assets/rules.json'}) async {
    // 1. Try dynamic file
    try {
      final updatesDir = await getUpdatesDirectory();
      final dynamicFile = File('${updatesDir.path}/rules.json');
      if (await dynamicFile.exists()) {
        final jsonStr = await dynamicFile.readAsString();
        final val = validateRulesJson(jsonStr);
        if (val.isValid) {
          _rulesSource = ModelSourceType.dynamic;
          final version = val.metadata['version'] as String? ?? _currentVersion;
          _addAuditLog(
            eventType: 'LOAD_DYNAMIC',
            assetType: 'rules',
            source: dynamicFile.path,
            version: version,
            status: 'success',
            details: 'Loaded dynamic rules database (${val.metadata['ruleCount']} rules)',
          );
          return jsonStr;
        } else {
          _addAuditLog(
            eventType: 'VALIDATION_FAILED',
            assetType: 'rules',
            source: dynamicFile.path,
            version: _currentVersion,
            status: 'warning',
            details: 'Dynamic rules validation failed: ${val.errorMessage}',
          );
        }
      }
    } catch (e) {
      _addAuditLog(
        eventType: 'LOAD_ERROR',
        assetType: 'rules',
        source: 'dynamic_updates',
        version: _currentVersion,
        status: 'warning',
        details: 'Error reading dynamic rules file: $e',
      );
    }

    // 2. Fallback to static bundle asset
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      final val = validateRulesJson(jsonStr);
      if (val.isValid) {
        _rulesSource = ModelSourceType.staticAsset;
        final version = val.metadata['version'] as String? ?? '1.0.0';
        _addAuditLog(
          eventType: 'LOAD_STATIC_FALLBACK',
          assetType: 'rules',
          source: assetPath,
          version: version,
          status: 'success',
          details: 'Loaded static bundle rules (${val.metadata['ruleCount']} rules)',
        );
        return jsonStr;
      }
    } catch (e) {
      _addAuditLog(
        eventType: 'LOAD_ERROR',
        assetType: 'rules',
        source: assetPath,
        version: '1.0.0',
        status: 'failure',
        details: 'Failed to load static rules asset: $e',
      );
    }

    _rulesSource = ModelSourceType.fallbackHeuristic;
    return null;
  }

  /// Loads Vocab string, prioritizing dynamic update directory with fallback to static asset.
  Future<String?> loadVocabString({String assetPath = 'assets/vocab.txt'}) async {
    // 1. Try dynamic file
    try {
      final updatesDir = await getUpdatesDirectory();
      final dynamicFile = File('${updatesDir.path}/vocab.txt');
      if (await dynamicFile.exists()) {
        final vocabStr = await dynamicFile.readAsString();
        final val = validateVocabString(vocabStr);
        if (val.isValid) {
          _vocabSource = ModelSourceType.dynamic;
          _addAuditLog(
            eventType: 'LOAD_DYNAMIC',
            assetType: 'vocab',
            source: dynamicFile.path,
            version: _currentVersion,
            status: 'success',
            details: 'Loaded dynamic vocab file (${val.metadata['tokenCount']} tokens)',
          );
          return vocabStr;
        } else {
          _addAuditLog(
            eventType: 'VALIDATION_FAILED',
            assetType: 'vocab',
            source: dynamicFile.path,
            version: _currentVersion,
            status: 'warning',
            details: 'Dynamic vocab validation failed: ${val.errorMessage}',
          );
        }
      }
    } catch (e) {
      _addAuditLog(
        eventType: 'LOAD_ERROR',
        assetType: 'vocab',
        source: 'dynamic_updates',
        version: _currentVersion,
        status: 'warning',
        details: 'Error reading dynamic vocab file: $e',
      );
    }

    // 2. Fallback to static bundle asset
    try {
      final vocabStr = await rootBundle.loadString(assetPath);
      final val = validateVocabString(vocabStr);
      if (val.isValid) {
        _vocabSource = ModelSourceType.staticAsset;
        _addAuditLog(
          eventType: 'LOAD_STATIC_FALLBACK',
          assetType: 'vocab',
          source: assetPath,
          version: '1.0.0',
          status: 'success',
          details: 'Loaded static bundle vocab file (${val.metadata['tokenCount']} tokens)',
        );
        return vocabStr;
      }
    } catch (e) {
      _addAuditLog(
        eventType: 'LOAD_ERROR',
        assetType: 'vocab',
        source: assetPath,
        version: '1.0.0',
        status: 'failure',
        details: 'Failed to load static vocab asset: $e',
      );
    }

    _vocabSource = ModelSourceType.fallbackHeuristic;
    return null;
  }

  // --- Dynamic Model Update Management API ---

  /// Applies dynamic ML updates by validating and writing new asset files to local storage.
  Future<bool> updateModelAssets({
    Uint8List? tfliteBytes,
    String? rulesJson,
    String? vocabText,
    String? version,
    Map<String, dynamic>? metadata,
  }) async {
    final newVersion = version ?? '2.0.0-dynamic-${DateTime.now().millisecondsSinceEpoch}';

    // Validate inputs provided
    if (tfliteBytes != null) {
      final val = validateTfliteBuffer(tfliteBytes);
      if (!val.isValid) {
        _addAuditLog(
          eventType: 'UPDATE_FAILED',
          assetType: 'tflite',
          source: 'update_payload',
          version: newVersion,
          status: 'failure',
          details: 'TFLite validation failed: ${val.errorMessage}',
        );
        return false;
      }
    }

    if (rulesJson != null) {
      final val = validateRulesJson(rulesJson);
      if (!val.isValid) {
        _addAuditLog(
          eventType: 'UPDATE_FAILED',
          assetType: 'rules',
          source: 'update_payload',
          version: newVersion,
          status: 'failure',
          details: 'Rules JSON validation failed: ${val.errorMessage}',
        );
        return false;
      }
    }

    if (vocabText != null) {
      final val = validateVocabString(vocabText);
      if (!val.isValid) {
        _addAuditLog(
          eventType: 'UPDATE_FAILED',
          assetType: 'vocab',
          source: 'update_payload',
          version: newVersion,
          status: 'failure',
          details: 'Vocab validation failed: ${val.errorMessage}',
        );
        return false;
      }
    }

    try {
      final updatesDir = await getUpdatesDirectory();

      if (tfliteBytes != null) {
        final file = File('${updatesDir.path}/model.tflite');
        await file.writeAsBytes(tfliteBytes);
      }

      if (rulesJson != null) {
        final file = File('${updatesDir.path}/rules.json');
        await file.writeAsString(rulesJson);
      }

      if (vocabText != null) {
        final file = File('${updatesDir.path}/vocab.txt');
        await file.writeAsString(vocabText);
      }

      // Write manifest
      _currentVersion = newVersion;
      final manifestMap = {
        'version': newVersion,
        'updatedAt': DateTime.now().toIso8601String(),
        'hasTflite': tfliteBytes != null,
        'hasRules': rulesJson != null,
        'hasVocab': vocabText != null,
        'metadata': metadata ?? {},
      };
      final manifestFile = File('${updatesDir.path}/manifest.json');
      await manifestFile.writeAsString(json.encode(manifestMap));

      _addAuditLog(
        eventType: 'UPDATE_SUCCESS',
        assetType: 'all',
        source: updatesDir.path,
        version: newVersion,
        status: 'success',
        details: 'Dynamic model assets updated successfully to v$newVersion',
      );

      return true;
    } catch (e) {
      _addAuditLog(
        eventType: 'UPDATE_FAILED',
        assetType: 'all',
        source: 'filesystem',
        version: newVersion,
        status: 'failure',
        details: 'Failed writing dynamic assets: $e',
      );
      return false;
    }
  }

  /// Removes local dynamic ML updates and resets model sources to bundle defaults.
  Future<void> clearDynamicUpdates() async {
    try {
      final updatesDir = await getUpdatesDirectory();
      if (await updatesDir.exists()) {
        await updatesDir.delete(recursive: true);
      }
      _currentVersion = '1.0.0-bundled';
      _tfliteSource = ModelSourceType.staticAsset;
      _rulesSource = ModelSourceType.staticAsset;
      _vocabSource = ModelSourceType.staticAsset;

      _addAuditLog(
        eventType: 'CLEAR_UPDATES',
        assetType: 'all',
        source: updatesDir.path,
        version: _currentVersion,
        status: 'success',
        details: 'Cleared dynamic ML updates, restored static bundle defaults',
      );
    } catch (e) {
      _addAuditLog(
        eventType: 'CLEAR_ERROR',
        assetType: 'all',
        source: 'filesystem',
        version: _currentVersion,
        status: 'failure',
        details: 'Failed to clear dynamic ML updates: $e',
      );
    }
  }
}
