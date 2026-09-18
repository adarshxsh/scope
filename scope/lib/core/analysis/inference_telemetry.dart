import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Individual telemetry sample capturing model inference performance metrics,
/// execution stage latencies, model status, and audit logs on-device.
class InferenceTelemetryRecord {
  /// Unique telemetry event ID.
  final String id;

  /// Stable notification ID or hashed reference (no raw content).
  final String notificationId;

  /// Timestamp when inference was executed.
  final DateTime timestamp;

  /// Latency of feature extraction in microseconds.
  final int featureExtractionUs;

  /// Latency of rule engine matching in microseconds.
  final int ruleEngineUs;

  /// Latency of TFLite model execution in microseconds.
  final int modelInferenceUs;

  /// Total end-to-end pipeline latency in microseconds.
  final int totalPipelineUs;

  /// Whether the TFLite model was active and loaded during prediction.
  final bool isModelLoaded;

  /// Whether heuristic fallback was triggered due to uninitialized model or error.
  final bool isFallbackUsed;

  /// Score predicted by TFLite model or heuristic (0.0 to 1.0).
  final double predictedScore;

  /// Optional rule engine score (0.0 to 1.0).
  final double? ruleScore;

  /// Final fused score after combining rules and overrides (0.0 to 1.0).
  final double finalFusedScore;

  /// Final priority classification resolved by policy engine ('critical'|'high'|'medium'|'low').
  final String resolvedPriority;

  /// Category classified by the pipeline.
  final String classifiedCategory;

  /// Version of rules engine used.
  final String? ruleVersion;

  /// Version of classification/ML model used.
  final String? modelVersion;

  /// Sanitized package name (e.g., com.whatsapp).
  final String sanitizedPackage;

  /// Flag confirming PII redaction guardrails were strictly applied.
  final bool hasPiiRedacted;

  /// Execution status: 'success', 'fallback', or 'error'.
  final String status;

  /// Audit log message or exception trace if fallback/error occurred.
  final String? errorLog;

  const InferenceTelemetryRecord({
    required this.id,
    required this.notificationId,
    required this.timestamp,
    required this.featureExtractionUs,
    required this.ruleEngineUs,
    required this.modelInferenceUs,
    required this.totalPipelineUs,
    required this.isModelLoaded,
    required this.isFallbackUsed,
    required this.predictedScore,
    this.ruleScore,
    required this.finalFusedScore,
    required this.resolvedPriority,
    required this.classifiedCategory,
    this.ruleVersion,
    this.modelVersion,
    required this.sanitizedPackage,
    this.hasPiiRedacted = true,
    required this.status,
    this.errorLog,
  });

  /// Total pipeline latency in milliseconds.
  double get totalPipelineMs => totalPipelineUs / 1000.0;

  /// Model inference latency in milliseconds.
  double get modelInferenceMs => modelInferenceUs / 1000.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'notificationId': notificationId,
      'timestamp': timestamp.toIso8601String(),
      'featureExtractionUs': featureExtractionUs,
      'ruleEngineUs': ruleEngineUs,
      'modelInferenceUs': modelInferenceUs,
      'totalPipelineUs': totalPipelineUs,
      'isModelLoaded': isModelLoaded,
      'isFallbackUsed': isFallbackUsed,
      'predictedScore': predictedScore,
      'ruleScore': ruleScore,
      'finalFusedScore': finalFusedScore,
      'resolvedPriority': resolvedPriority,
      'classifiedCategory': classifiedCategory,
      'ruleVersion': ruleVersion,
      'modelVersion': modelVersion,
      'sanitizedPackage': sanitizedPackage,
      'hasPiiRedacted': hasPiiRedacted,
      'status': status,
      'errorLog': errorLog,
    };
  }

  @override
  String toString() {
    return 'InferenceTelemetryRecord(id: $id, total: ${totalPipelineMs.toStringAsFixed(2)}ms, model: ${modelInferenceMs.toStringAsFixed(2)}ms, fallback: $isFallbackUsed, status: $status)';
  }
}

/// Aggregated performance telemetry summary.
class TelemetrySummary {
  final int totalInferences;
  final double avgTotalLatencyMs;
  final double p50LatencyMs;
  final double p95LatencyMs;
  final double p99LatencyMs;
  final double avgFeatureExtractionMs;
  final double avgRuleEngineMs;
  final double avgModelInferenceMs;
  final double fallbackRatePercent;
  final double modelSuccessRatePercent;
  final int fallbackCount;
  final int errorCount;

  const TelemetrySummary({
    required this.totalInferences,
    required this.avgTotalLatencyMs,
    required this.p50LatencyMs,
    required this.p95LatencyMs,
    required this.p99LatencyMs,
    required this.avgFeatureExtractionMs,
    required this.avgRuleEngineMs,
    required this.avgModelInferenceMs,
    required this.fallbackRatePercent,
    required this.modelSuccessRatePercent,
    required this.fallbackCount,
    required this.errorCount,
  });
}

/// Singleton manager for tracking, buffering, analyzing, and auditing
/// model inference performance telemetry locally on-device.
class ModelInferenceTelemetryTracker {
  static ModelInferenceTelemetryTracker? _instance;
  final int maxCapacity;
  final Queue<InferenceTelemetryRecord> _buffer = Queue<InferenceTelemetryRecord>();
  final List<String> _auditLogs = [];
  static const int _maxAuditLogs = 100;

  ModelInferenceTelemetryTracker._({this.maxCapacity = 200});

  static ModelInferenceTelemetryTracker get instance =>
      _instance ??= ModelInferenceTelemetryTracker._();

  /// Creates a custom tracker instance (e.g. for testing with custom buffer sizes).
  factory ModelInferenceTelemetryTracker.withCapacity(int maxCapacity) {
    return ModelInferenceTelemetryTracker._(maxCapacity: maxCapacity);
  }

  /// Records a new inference telemetry event in the bounded ring buffer.
  void record(InferenceTelemetryRecord record) {
    while (_buffer.length >= maxCapacity) {
      _buffer.removeFirst();
    }
    _buffer.addLast(record);

    if (record.isFallbackUsed || record.status == 'error' || record.errorLog != null) {
      final timeStr = record.timestamp.toIso8601String().substring(11, 19);
      final logEntry =
          '[$timeStr] Status: ${record.status.toUpperCase()} | Pkg: ${record.sanitizedPackage} | Fallback: ${record.isFallbackUsed} | Reason: ${record.errorLog ?? "Fallback heuristic triggered"}';
      _addAuditLog(logEntry);
    }
  }

  /// Records an inference failure or exception into audit logs.
  void recordError({
    required String notificationId,
    required String packageName,
    required String error,
    required int totalUs,
  }) {
    final sanitizedPkg = sanitizePackageName(packageName);
    final telemetryRec = InferenceTelemetryRecord(
      id: 'tel_err_${DateTime.now().microsecondsSinceEpoch}',
      notificationId: notificationId,
      timestamp: DateTime.now(),
      featureExtractionUs: 0,
      ruleEngineUs: 0,
      modelInferenceUs: 0,
      totalPipelineUs: totalUs,
      isModelLoaded: false,
      isFallbackUsed: true,
      predictedScore: 0.0,
      finalFusedScore: 0.0,
      resolvedPriority: 'low',
      classifiedCategory: 'unknown',
      sanitizedPackage: sanitizedPkg,
      status: 'error',
      errorLog: error,
    );
    record(telemetryRec);
  }

  void _addAuditLog(String log) {
    _auditLogs.add(log);
    if (_auditLogs.length > _maxAuditLogs) {
      _auditLogs.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('TELEMETRY AUDIT LOG: $log');
    }
  }

  /// Sanitizes package names to prevent accidental inclusion of sensitive parameters.
  static String sanitizePackageName(String pkg) {
    if (pkg.isEmpty) return 'unknown.app';
    final clean = pkg.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
    return clean.isEmpty ? 'unknown.app' : clean;
  }

  /// Returns unmodifiable list of buffered telemetry records.
  List<InferenceTelemetryRecord> get records => List.unmodifiable(_buffer);

  /// Returns unmodifiable list of recent audit logs.
  List<String> get auditLogs => List.unmodifiable(_auditLogs);

  /// Number of recorded events currently in buffer.
  int get count => _buffer.length;

  /// Computes comprehensive statistical summary over recorded telemetry events.
  TelemetrySummary computeSummary() {
    if (_buffer.isEmpty) {
      return const TelemetrySummary(
        totalInferences: 0,
        avgTotalLatencyMs: 0.0,
        p50LatencyMs: 0.0,
        p95LatencyMs: 0.0,
        p99LatencyMs: 0.0,
        avgFeatureExtractionMs: 0.0,
        avgRuleEngineMs: 0.0,
        avgModelInferenceMs: 0.0,
        fallbackRatePercent: 0.0,
        modelSuccessRatePercent: 100.0,
        fallbackCount: 0,
        errorCount: 0,
      );
    }

    final total = _buffer.length;
    final latencies = _buffer.map((r) => r.totalPipelineMs).toList()..sort();

    double sumTotalMs = 0.0;
    double sumExtractMs = 0.0;
    double sumRuleMs = 0.0;
    double sumModelMs = 0.0;
    int fallbacks = 0;
    int errors = 0;

    for (final r in _buffer) {
      sumTotalMs += r.totalPipelineMs;
      sumExtractMs += r.featureExtractionUs / 1000.0;
      sumRuleMs += r.ruleEngineUs / 1000.0;
      sumModelMs += r.modelInferenceUs / 1000.0;
      if (r.isFallbackUsed) fallbacks++;
      if (r.status == 'error') errors++;
    }

    final avgTotalMs = sumTotalMs / total;
    final avgExtractMs = sumExtractMs / total;
    final avgRuleMs = sumRuleMs / total;
    final avgModelMs = sumModelMs / total;

    final p50 = _percentile(latencies, 0.50);
    final p95 = _percentile(latencies, 0.95);
    final p99 = _percentile(latencies, 0.99);

    final fallbackPercent = (fallbacks / total) * 100.0;
    final modelSuccessPercent = ((total - errors) / total) * 100.0;

    return TelemetrySummary(
      totalInferences: total,
      avgTotalLatencyMs: avgTotalMs,
      p50LatencyMs: p50,
      p95LatencyMs: p95,
      p99LatencyMs: p99,
      avgFeatureExtractionMs: avgExtractMs,
      avgRuleEngineMs: avgRuleMs,
      avgModelInferenceMs: avgModelMs,
      fallbackRatePercent: fallbackPercent,
      modelSuccessRatePercent: modelSuccessPercent,
      fallbackCount: fallbacks,
      errorCount: errors,
    );
  }

  static double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return 0.0;
    if (sortedValues.length == 1) return sortedValues.first;
    final index = (percentile * (sortedValues.length - 1)).round();
    final clampedIndex = index.clamp(0, sortedValues.length - 1);
    return sortedValues[clampedIndex];
  }

  /// Clears all stored telemetry records and audit logs.
  void clear() {
    _buffer.clear();
    _auditLogs.clear();
  }
}
