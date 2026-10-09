import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:scope/database/attention_database.dart';

/// Single event log representing model inference performance telemetry.
class InferenceTelemetryLog {
  final int? id;
  final int timestamp;
  final int inferenceTimeUs;
  final int engineLatencyMs;
  final String modelVersion;
  final String engineVersion;
  final bool isFallback;
  final bool isError;
  final String? errorMessage;
  final String? notificationId;
  final String? category;

  const InferenceTelemetryLog({
    this.id,
    required this.timestamp,
    required this.inferenceTimeUs,
    required this.engineLatencyMs,
    required this.modelVersion,
    required this.engineVersion,
    this.isFallback = false,
    this.isError = false,
    this.errorMessage,
    this.notificationId,
    this.category,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'inferenceTimeUs': inferenceTimeUs,
      'engineLatencyMs': engineLatencyMs,
      'modelVersion': modelVersion,
      'engineVersion': engineVersion,
      'isFallback': isFallback,
      'isError': isError,
      'errorMessage': errorMessage,
      'notificationId': notificationId,
      'category': category,
    };
  }

  factory InferenceTelemetryLog.fromMap(Map<String, dynamic> map) {
    return InferenceTelemetryLog(
      id: map['id'] as int?,
      timestamp: map['timestamp'] as int? ?? 0,
      inferenceTimeUs: map['inferenceTimeUs'] as int? ?? 0,
      engineLatencyMs: map['engineLatencyMs'] as int? ?? 0,
      modelVersion: map['modelVersion'] as String? ?? 'unknown',
      engineVersion: map['engineVersion'] as String? ?? 'unknown',
      isFallback: map['isFallback'] as bool? ?? false,
      isError: map['isError'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String?,
      notificationId: map['notificationId'] as String?,
      category: map['category'] as String?,
    );
  }

  @override
  String toString() {
    return 'InferenceTelemetryLog(id: $id, inferenceTimeUs: ${inferenceTimeUs}us, engineLatencyMs: ${engineLatencyMs}ms, modelVersion: $modelVersion, isFallback: $isFallback, isError: $isError)';
  }
}

/// Summary statistics aggregated over a window or session of inference logs.
class InferenceTelemetryStats {
  final int totalInferences;
  final double avgInferenceTimeUs;
  final double p95InferenceTimeUs;
  final int minInferenceTimeUs;
  final int maxInferenceTimeUs;
  final int fallbackCount;
  final double fallbackRate;
  final int failureCount;
  final double failureRate;
  final double avgEngineLatencyMs;

  const InferenceTelemetryStats({
    required this.totalInferences,
    required this.avgInferenceTimeUs,
    required this.p95InferenceTimeUs,
    required this.minInferenceTimeUs,
    required this.maxInferenceTimeUs,
    required this.fallbackCount,
    required this.fallbackRate,
    required this.failureCount,
    required this.failureRate,
    required this.avgEngineLatencyMs,
  });

  factory InferenceTelemetryStats.empty() {
    return const InferenceTelemetryStats(
      totalInferences: 0,
      avgInferenceTimeUs: 0.0,
      p95InferenceTimeUs: 0.0,
      minInferenceTimeUs: 0,
      maxInferenceTimeUs: 0,
      fallbackCount: 0,
      fallbackRate: 0.0,
      failureCount: 0,
      failureRate: 0.0,
      avgEngineLatencyMs: 0.0,
    );
  }

  @override
  String toString() {
    return 'InferenceTelemetryStats(total: $totalInferences, avgUs: ${avgInferenceTimeUs.toStringAsFixed(1)}, p95Us: ${p95InferenceTimeUs.toStringAsFixed(1)}, fallbackRate: ${(fallbackRate * 100).toStringAsFixed(1)}%, failureRate: ${(failureRate * 100).toStringAsFixed(1)}%)';
  }
}

/// In-memory ring buffer holding recent inference telemetry logs and calculating metrics.
class InferenceTelemetryBuffer {
  final int maxCapacity;
  final List<InferenceTelemetryLog> _buffer = [];

  InferenceTelemetryBuffer({this.maxCapacity = 500});

  /// Adds a new log event to the buffer, bounded by [maxCapacity].
  void record(InferenceTelemetryLog log) {
    try {
      _buffer.add(log);
      if (_buffer.length > maxCapacity) {
        _buffer.removeAt(0);
      }
    } catch (e) {
      debugPrint('InferenceTelemetryBuffer error: $e');
    }
  }

  /// Returns unmodifiable view of recent logs.
  List<InferenceTelemetryLog> get logs => List.unmodifiable(_buffer.reversed);

  /// Computes aggregate statistics over current buffer contents.
  InferenceTelemetryStats getStats() {
    if (_buffer.isEmpty) {
      return InferenceTelemetryStats.empty();
    }

    final total = _buffer.length;
    int sumInferenceUs = 0;
    int sumEngineMs = 0;
    int fallbacks = 0;
    int failures = 0;
    int minUs = _buffer.first.inferenceTimeUs;
    int maxUs = _buffer.first.inferenceTimeUs;

    final inferenceTimesUs = <int>[];

    for (final log in _buffer) {
      final us = math.max(0, log.inferenceTimeUs);
      inferenceTimesUs.add(us);
      sumInferenceUs += us;
      sumEngineMs += math.max(0, log.engineLatencyMs);

      if (us < minUs) minUs = us;
      if (us > maxUs) maxUs = us;

      if (log.isFallback) fallbacks++;
      if (log.isError) failures++;
    }

    inferenceTimesUs.sort();
    final p95Index = ((total * 0.95) - 1).round().clamp(0, total - 1);
    final p95Us = inferenceTimesUs[p95Index].toDouble();

    return InferenceTelemetryStats(
      totalInferences: total,
      avgInferenceTimeUs: sumInferenceUs / total,
      p95InferenceTimeUs: p95Us,
      minInferenceTimeUs: minUs,
      maxInferenceTimeUs: maxUs,
      fallbackCount: fallbacks,
      fallbackRate: fallbacks / total,
      failureCount: failures,
      failureRate: failures / total,
      avgEngineLatencyMs: sumEngineMs / total,
    );
  }

  /// Clears the buffer.
  void clear() {
    _buffer.clear();
  }
}

/// Central manager and singleton coordinator for model inference telemetry.
class InferenceTelemetryManager {
  static InferenceTelemetryManager? _instance;
  final InferenceTelemetryBuffer _buffer = InferenceTelemetryBuffer();
  AttentionDatabase? _db;

  InferenceTelemetryManager._();

  static InferenceTelemetryManager get instance => _instance ??= InferenceTelemetryManager._();

  /// Attaches or updates the database reference for persistence.
  void setDatabase(AttentionDatabase? db) {
    _db = db;
  }

  /// Records an inference event in memory and optionally persists to DB.
  Future<void> recordInference({
    required int inferenceTimeUs,
    required int engineLatencyMs,
    required String modelVersion,
    required String engineVersion,
    bool isFallback = false,
    bool isError = false,
    String? errorMessage,
    String? notificationId,
    String? category,
  }) async {
    try {
      final log = InferenceTelemetryLog(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        inferenceTimeUs: math.max(0, inferenceTimeUs),
        engineLatencyMs: math.max(0, engineLatencyMs),
        modelVersion: modelVersion,
        engineVersion: engineVersion,
        isFallback: isFallback,
        isError: isError,
        errorMessage: errorMessage,
        notificationId: notificationId,
        category: category,
      );

      _buffer.record(log);

      if (_db != null) {
        await _db!.inferenceTelemetryDao.insertTelemetry(
          InferenceTelemetryEntry(
            id: 0,
            timestamp: log.timestamp,
            inferenceTimeUs: log.inferenceTimeUs,
            engineLatencyMs: log.engineLatencyMs,
            modelVersion: log.modelVersion,
            engineVersion: log.engineVersion,
            isFallback: log.isFallback,
            isError: log.isError,
            errorMessage: log.errorMessage,
            notificationId: log.notificationId,
            category: log.category,
          ),
        );
      }
    } catch (e) {
      // Guardrail: Never let telemetry recording break AI or app execution
      debugPrint('InferenceTelemetryManager recordInference error: $e');
    }
  }

  /// Returns aggregated telemetry metrics.
  InferenceTelemetryStats getStats() => _buffer.getStats();

  /// Returns recent inference logs from memory.
  List<InferenceTelemetryLog> getRecentLogs() => _buffer.logs;

  /// Clears in-memory buffer and database telemetry entries.
  Future<void> clear() async {
    _buffer.clear();
    try {
      if (_db != null) {
        await _db!.inferenceTelemetryDao.clearAll();
      }
    } catch (e) {
      debugPrint('InferenceTelemetryManager clear error: $e');
    }
  }
}
