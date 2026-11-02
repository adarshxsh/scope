import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

/// Data structure representing a single microsecond TFLite inference event.
class InferenceRecord {
  final int inferenceTimeUs;
  final bool isFallback;
  final bool isError;
  final String modelVersion;
  final DateTime timestamp;

  InferenceRecord({
    required this.inferenceTimeUs,
    required this.isFallback,
    required this.isError,
    required this.modelVersion,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Calculated summary statistics for a telemetry session or buffer snapshot.
class TelemetryStats {
  final int totalInferences;
  final int errorCount;
  final int fallbackCount;
  final double fallbackRate; // Fraction (0.0 to 1.0)
  final int p50LatencyUs;
  final int p90LatencyUs;
  final int p95LatencyUs;
  final String? modelVersion;

  const TelemetryStats({
    required this.totalInferences,
    required this.errorCount,
    required this.fallbackCount,
    required this.fallbackRate,
    required this.p50LatencyUs,
    required this.p90LatencyUs,
    required this.p95LatencyUs,
    this.modelVersion,
  });

  /// Fallback percentage (0.0 to 100.0)
  double get fallbackPercentage => fallbackRate * 100.0;
}

/// Computes percentile for a list of integer latencies using nearest-rank index calculation.
int computePercentile(List<int> sortedLatencies, double percentile) {
  if (sortedLatencies.isEmpty) return 0;
  if (sortedLatencies.length == 1) return sortedLatencies.first;

  final rank = (percentile * sortedLatencies.length).ceil();
  final index = (rank - 1).clamp(0, sortedLatencies.length - 1);
  return sortedLatencies[index];
}

/// Low-latency in-memory ring buffer recording inference timing and execution status.
class InferenceTelemetryBuffer {
  static final InferenceTelemetryBuffer _instance = InferenceTelemetryBuffer();
  static InferenceTelemetryBuffer get instance => _instance;

  final int capacity;
  final List<InferenceRecord> _buffer = [];

  InferenceTelemetryBuffer({this.capacity = 500});

  /// Records an inference event into the ring buffer.
  /// Evicts the oldest record when capacity is exceeded. Non-blocking with zero disk I/O.
  void record({
    required int inferenceTimeUs,
    required bool isFallback,
    required bool isError,
    required String modelVersion,
    DateTime? timestamp,
  }) {
    if (_buffer.length >= capacity) {
      _buffer.removeAt(0);
    }
    _buffer.add(InferenceRecord(
      inferenceTimeUs: inferenceTimeUs,
      isFallback: isFallback,
      isError: isError,
      modelVersion: modelVersion,
      timestamp: timestamp,
    ));
  }

  /// Returns an unmodifiable snapshot of buffered inference records.
  List<InferenceRecord> get records => List.unmodifiable(_buffer);

  /// Returns the current number of records in the buffer.
  int get length => _buffer.length;

  /// Returns whether the buffer is empty.
  bool get isEmpty => _buffer.isEmpty;

  /// Clears all buffered records.
  void clear() {
    _buffer.clear();
  }

  /// Computes real-time session statistics from buffered records without modifying the buffer.
  TelemetryStats getRealtimeSessionStats() {
    if (_buffer.isEmpty) {
      return const TelemetryStats(
        totalInferences: 0,
        errorCount: 0,
        fallbackCount: 0,
        fallbackRate: 0.0,
        p50LatencyUs: 0,
        p90LatencyUs: 0,
        p95LatencyUs: 0,
        modelVersion: null,
      );
    }

    final total = _buffer.length;
    int errors = 0;
    int fallbacks = 0;
    final latencies = <int>[];
    String? latestModelVersion;

    for (final record in _buffer) {
      if (record.isError) errors++;
      if (record.isFallback) fallbacks++;
      latencies.add(record.inferenceTimeUs);
      latestModelVersion = record.modelVersion;
    }

    latencies.sort();

    final p50 = computePercentile(latencies, 0.50);
    final p90 = computePercentile(latencies, 0.90);
    final p95 = computePercentile(latencies, 0.95);

    return TelemetryStats(
      totalInferences: total,
      errorCount: errors,
      fallbackCount: fallbacks,
      fallbackRate: total > 0 ? fallbacks / total : 0.0,
      p50LatencyUs: p50,
      p90LatencyUs: p90,
      p95LatencyUs: p95,
      modelVersion: latestModelVersion,
    );
  }

  /// Periodically aggregates buffered metrics, persists summary statistics to Drift DB,
  /// clears the flushed records, and enforces a 30-day retention cleanup.
  Future<TelemetryStats?> flush(AttentionDatabase db) async {
    if (_buffer.isEmpty) return null;

    final snapshot = List<InferenceRecord>.from(_buffer);
    _buffer.clear();

    final periodStart = snapshot.first.timestamp;
    final periodEnd = snapshot.last.timestamp;

    final total = snapshot.length;
    int errors = 0;
    int fallbacks = 0;
    final latencies = <int>[];
    String? latestModelVersion;

    for (final record in snapshot) {
      if (record.isError) errors++;
      if (record.isFallback) fallbacks++;
      latencies.add(record.inferenceTimeUs);
      latestModelVersion = record.modelVersion;
    }

    latencies.sort();

    final p50 = computePercentile(latencies, 0.50);
    final p90 = computePercentile(latencies, 0.90);
    final p95 = computePercentile(latencies, 0.95);

    final stats = TelemetryStats(
      totalInferences: total,
      errorCount: errors,
      fallbackCount: fallbacks,
      fallbackRate: total > 0 ? fallbacks / total : 0.0,
      p50LatencyUs: p50,
      p90LatencyUs: p90,
      p95LatencyUs: p95,
      modelVersion: latestModelVersion,
    );

    await db.inferenceTelemetryDao.insertTelemetry(
      InferenceTelemetryTableCompanion.insert(
        periodStartMs: periodStart.millisecondsSinceEpoch,
        periodEndMs: periodEnd.millisecondsSinceEpoch,
        totalInferences: total,
        errorCount: Value(errors),
        fallbackCount: Value(fallbacks),
        p50LatencyUs: p50,
        p90LatencyUs: p90,
        p95LatencyUs: p95,
        modelVersion: Value(latestModelVersion),
        createdAt: Value(DateTime.now()),
      ),
    );

    // Enforce 30-day retention cap
    final retentionCutoff = DateTime.now().subtract(const Duration(days: 30));
    await db.inferenceTelemetryDao.deleteOlderThan(retentionCutoff);

    return stats;
  }
}
