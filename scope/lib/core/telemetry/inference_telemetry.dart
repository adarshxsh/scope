import 'dart:math' as math;

/// Single sanitized performance record for a model inference execution.
class InferenceTelemetryRecord {
  final int id;
  final int timestamp; // Milliseconds since epoch
  final int inferenceTimeUs; // Execution time in microseconds
  final int totalLatencyMs; // Total processing time in milliseconds
  final bool isFallback; // True if fallback heuristic was used
  final bool isSuccess; // True if execution completed successfully
  final String modelVersion; // e.g. '1.0.0-tflite' or 'fallback-heuristics'
  final String? classifiedCategory; // Sanitized category name

  InferenceTelemetryRecord({
    int? id,
    int? timestamp,
    required int inferenceTimeUs,
    required int totalLatencyMs,
    this.isFallback = false,
    this.isSuccess = true,
    required String modelVersion,
    String? classifiedCategory,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch,
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch,
        inferenceTimeUs = inferenceTimeUs < 0 ? 0 : inferenceTimeUs,
        totalLatencyMs = totalLatencyMs < 0 ? 0 : totalLatencyMs,
        modelVersion = _sanitizeString(modelVersion, defaultValue: 'unknown'),
        classifiedCategory = _sanitizeCategory(classifiedCategory);

  /// Sanitizes category string to ensure no raw text or PII is stored.
  static String? _sanitizeCategory(String? category) {
    if (category == null || category.trim().isEmpty) return null;
    final cleaned = category.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (cleaned.length > 32) return cleaned.substring(0, 32);
    return cleaned;
  }

  static String _sanitizeString(String val, {String defaultValue = ''}) {
    final cleaned = val.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '');
    if (cleaned.isEmpty) return defaultValue;
    if (cleaned.length > 32) return cleaned.substring(0, 32);
    return cleaned;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'inferenceTimeUs': inferenceTimeUs,
      'totalLatencyMs': totalLatencyMs,
      'isFallback': isFallback,
      'isSuccess': isSuccess,
      'modelVersion': modelVersion,
      'classifiedCategory': classifiedCategory,
    };
  }

  factory InferenceTelemetryRecord.fromMap(Map<String, dynamic> map) {
    return InferenceTelemetryRecord(
      id: map['id'] as int?,
      timestamp: map['timestamp'] as int?,
      inferenceTimeUs: map['inferenceTimeUs'] as int? ?? 0,
      totalLatencyMs: map['totalLatencyMs'] as int? ?? 0,
      isFallback: map['isFallback'] as bool? ?? false,
      isSuccess: map['isSuccess'] as bool? ?? true,
      modelVersion: map['modelVersion'] as String? ?? 'unknown',
      classifiedCategory: map['classifiedCategory'] as String?,
    );
  }
}

/// Aggregated performance telemetry metrics computed over the telemetry buffer.
class InferenceTelemetryMetrics {
  final int totalInferences;
  final double averageInferenceTimeUs;
  final double averageTotalLatencyMs;
  final double p95InferenceTimeUs;
  final int fallbackCount;
  final double fallbackRate;
  final int failureCount;

  const InferenceTelemetryMetrics({
    required this.totalInferences,
    required this.averageInferenceTimeUs,
    required this.averageTotalLatencyMs,
    required this.p95InferenceTimeUs,
    required this.fallbackCount,
    required this.fallbackRate,
    required this.failureCount,
  });

  static const InferenceTelemetryMetrics empty = InferenceTelemetryMetrics(
    totalInferences: 0,
    averageInferenceTimeUs: 0.0,
    averageTotalLatencyMs: 0.0,
    p95InferenceTimeUs: 0.0,
    fallbackCount: 0,
    fallbackRate: 0.0,
    failureCount: 0,
  );
}

/// In-memory bounded circular telemetry buffer and aggregation pipeline.
class InferenceTelemetryBuffer {
  static final InferenceTelemetryBuffer instance = InferenceTelemetryBuffer._();
  final int maxCapacity;
  final List<InferenceTelemetryRecord> _records = [];

  InferenceTelemetryBuffer({this.maxCapacity = 500});

  InferenceTelemetryBuffer._({this.maxCapacity = 500});

  /// Appends a new inference telemetry record, keeping size <= [maxCapacity].
  void record(InferenceTelemetryRecord record) {
    if (_records.length >= maxCapacity) {
      _records.removeAt(0); // FIFO eviction
    }
    _records.add(record);
  }

  /// Returns unmodifiable list of current buffered telemetry records.
  List<InferenceTelemetryRecord> get records => List.unmodifiable(_records);

  /// Clears all stored telemetry records.
  void clear() {
    _records.clear();
  }

  /// Computes summary performance metrics over the current buffer.
  InferenceTelemetryMetrics getMetrics() {
    if (_records.isEmpty) {
      return InferenceTelemetryMetrics.empty;
    }

    int sumUs = 0;
    int sumMs = 0;
    int fallbacks = 0;
    int failures = 0;
    final List<int> usList = [];

    for (final r in _records) {
      sumUs += r.inferenceTimeUs;
      sumMs += r.totalLatencyMs;
      usList.add(r.inferenceTimeUs);
      if (r.isFallback) fallbacks++;
      if (!r.isSuccess) failures++;
    }

    usList.sort();

    final total = _records.length;
    final avgUs = sumUs / total;
    final avgMs = sumMs / total;
    final p95Index = math.max(0, (total * 0.95).ceil() - 1);
    final p95Us = usList[p95Index].toDouble();
    final fallbackRate = fallbacks / total;

    return InferenceTelemetryMetrics(
      totalInferences: total,
      averageInferenceTimeUs: avgUs,
      averageTotalLatencyMs: avgMs,
      p95InferenceTimeUs: p95Us,
      fallbackCount: fallbacks,
      fallbackRate: fallbackRate,
      failureCount: failures,
    );
  }
}
