import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/model_audit_logger.dart';
import 'package:scope/core/analysis/model_verifier.dart';

/// Enum representing the current operational lifecycle state of the model.
enum ModelLifecycleState {
  uninitialized,
  loading,
  active,
  degraded,
  failed,
  updating,
}

/// Metadata describing active model properties and performance telemetry.
class ModelMetadata {
  final String modelVersion;
  final String sha256;
  final String assetPath;
  final int totalInferences;
  final int errorCount;
  final int fallbackCount;
  final double averageLatencyUs;
  final DateTime? loadedAt;

  const ModelMetadata({
    this.modelVersion = '1.0.0-default',
    this.sha256 = '',
    this.assetPath = 'assets/model.tflite',
    this.totalInferences = 0,
    this.errorCount = 0,
    this.fallbackCount = 0,
    this.averageLatencyUs = 0.0,
    this.loadedAt,
  });

  ModelMetadata copyWith({
    String? modelVersion,
    String? sha256,
    String? assetPath,
    int? totalInferences,
    int? errorCount,
    int? fallbackCount,
    double? averageLatencyUs,
    DateTime? loadedAt,
  }) {
    return ModelMetadata(
      modelVersion: modelVersion ?? this.modelVersion,
      sha256: sha256 ?? this.sha256,
      assetPath: assetPath ?? this.assetPath,
      totalInferences: totalInferences ?? this.totalInferences,
      errorCount: errorCount ?? this.errorCount,
      fallbackCount: fallbackCount ?? this.fallbackCount,
      averageLatencyUs: averageLatencyUs ?? this.averageLatencyUs,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }
}

/// Core Model Lifecycle Manager handling asset loading, cryptographic verification,
/// dynamic hot-reloading, thread-safe interpreter resource disposal, and fallback paths.
class ModelManager {
  static final ModelManager instance = ModelManager._();

  ModelLifecycleState _state = ModelLifecycleState.uninitialized;
  ModelMetadata _metadata = const ModelMetadata();
  Interpreter? _interpreter;

  ModelManager._();

  /// Current model lifecycle state.
  ModelLifecycleState get state => _state;

  /// Active model metadata and inference metrics.
  ModelMetadata get metadata => _metadata;

  /// Active TFLite interpreter instance (null if degraded or uninitialized).
  Interpreter? get interpreter => _interpreter;

  /// Returns whether a verified model interpreter is loaded and active.
  bool get isModelLoaded => _interpreter != null && _state == ModelLifecycleState.active;

  /// Initializes default bundled model from Flutter assets with verification and fallback error recovery.
  Future<bool> initialize({
    String assetPath = 'assets/model.tflite',
    String? expectedSha256,
  }) async {
    if (_interpreter != null && _state == ModelLifecycleState.active) {
      return true;
    }

    _state = ModelLifecycleState.loading;
    ModelAuditLogger.instance.log('LOADING', 'Initializing model asset from $assetPath...');

    try {
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      // Verify SHA-256 and FlatBuffer magic header
      final String digest = ModelVerifier.verifyBytes(
        bytes,
        expectedSha256: expectedSha256,
      );

      final newInterpreter = Interpreter.fromBuffer(bytes);

      _disposeInterpreter();
      _interpreter = newInterpreter;
      _state = ModelLifecycleState.active;
      _metadata = _metadata.copyWith(
        modelVersion: '1.0.0-tflite',
        sha256: digest,
        assetPath: assetPath,
        loadedAt: DateTime.now(),
      );

      ModelAuditLogger.instance.log(
        'ACTIVE',
        'Model initialized successfully from asset $assetPath. SHA-256: ${digest.substring(0, 8)}...',
        metadata: {'path': assetPath, 'sha256': digest, 'version': _metadata.modelVersion},
      );
      return true;
    } catch (e) {
      _state = ModelLifecycleState.degraded;
      _metadata = _metadata.copyWith(
        fallbackCount: _metadata.fallbackCount + 1,
        modelVersion: 'fallback-heuristics',
      );

      ModelAuditLogger.instance.log(
        'DEGRADED',
        'Model initialization failed: $e. Operating in degraded rule fallback mode.',
        metadata: {'error': e.toString()},
      );
      return false;
    }
  }

  /// Hot-reloads updated model from byte array with integrity verification and safe interpreter swap.
  Future<bool> hotReloadFromBytes(
    Uint8List bytes, {
    String? expectedSha256,
    String? version,
  }) async {
    final previousState = _state;
    _state = ModelLifecycleState.updating;
    ModelAuditLogger.instance.log('UPDATING', 'Hot-reloading model from memory buffer...');

    try {
      final String digest = ModelVerifier.verifyBytes(
        bytes,
        expectedSha256: expectedSha256,
      );

      final newInterpreter = Interpreter.fromBuffer(bytes);

      // Thread-safely dispose previous interpreter and replace
      _disposeInterpreter();
      _interpreter = newInterpreter;
      _state = ModelLifecycleState.active;
      _metadata = _metadata.copyWith(
        modelVersion: version ?? '2.0.0-ota',
        sha256: digest,
        assetPath: 'memory://buffer',
        loadedAt: DateTime.now(),
      );

      ModelAuditLogger.instance.log(
        'HOT_RELOAD_SUCCESS',
        'Hot-reloaded model successfully. Version: ${_metadata.modelVersion}, SHA-256: ${digest.substring(0, 8)}...',
        metadata: {'sha256': digest, 'version': _metadata.modelVersion},
      );
      return true;
    } catch (e) {
      if (_interpreter == null) {
        _state = ModelLifecycleState.degraded;
      } else {
        _state = previousState;
      }

      ModelAuditLogger.instance.log(
        'HOT_RELOAD_FAILED',
        'Hot-reload model verification failed: $e',
        metadata: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Hot-reloads model from local storage file.
  Future<bool> hotReloadFromFile(
    File file, {
    String? expectedSha256,
    String? version,
  }) async {
    if (!await file.exists()) {
      throw ModelVerificationException('File does not exist: ${file.path}');
    }
    final bytes = await file.readAsBytes();
    return hotReloadFromBytes(
      bytes,
      expectedSha256: expectedSha256,
      version: version,
    );
  }

  /// Records telemetry metrics for an inference run.
  void recordInference({
    required int latencyUs,
    required bool isError,
    required bool isFallback,
  }) {
    final total = _metadata.totalInferences + 1;
    final errors = isError ? _metadata.errorCount + 1 : _metadata.errorCount;
    final fallbacks = isFallback ? _metadata.fallbackCount + 1 : _metadata.fallbackCount;

    final prevAvg = _metadata.averageLatencyUs;
    final newAvg = prevAvg == 0.0 ? latencyUs.toDouble() : (prevAvg * (total - 1) + latencyUs) / total;

    _metadata = _metadata.copyWith(
      totalInferences: total,
      errorCount: errors,
      fallbackCount: fallbacks,
      averageLatencyUs: newAvg,
    );
  }

  void _disposeInterpreter() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
  }

  /// Disposes interpreter and resets lifecycle state.
  void dispose() {
    _disposeInterpreter();
    _state = ModelLifecycleState.uninitialized;
    ModelAuditLogger.instance.log('DISPOSED', 'ModelManager resources disposed.');
  }
}
