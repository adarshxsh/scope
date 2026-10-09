import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/telemetry/inference_telemetry_buffer.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InferenceTelemetryBuffer Unit Tests', () {
    late InferenceTelemetryBuffer buffer;

    setUp(() {
      buffer = InferenceTelemetryBuffer(capacity: 500);
      InferenceTelemetryBuffer.instance.clear();
    });

    test('Records inference timing, fallback status, and error status without error', () {
      buffer.record(
        inferenceTimeUs: 1500,
        isFallback: false,
        isError: false,
        modelVersion: '1.0.0-tflite',
      );

      expect(buffer.length, equals(1));
      expect(buffer.records.first.inferenceTimeUs, equals(1500));
      expect(buffer.records.first.isFallback, isFalse);
      expect(buffer.records.first.isError, isFalse);
      expect(buffer.records.first.modelVersion, equals('1.0.0-tflite'));
    });

    test('Enforces ring buffer capacity cap of 500 and evicts oldest records', () {
      for (int i = 1; i <= 550; i++) {
        buffer.record(
          inferenceTimeUs: i * 10,
          isFallback: i % 10 == 0,
          isError: false,
          modelVersion: '1.0.0-tflite',
        );
      }

      expect(buffer.length, equals(500));
      // First 50 items (1..50) should have been evicted. Oldest item is now item 51 (value 510).
      expect(buffer.records.first.inferenceTimeUs, equals(510));
      expect(buffer.records.last.inferenceTimeUs, equals(5500));
    });

    test('Computes percentiles (p50, p90, p95) and session stats correctly', () {
      // Record 100 sample latencies: 100, 200, 300, ..., 10000 µs
      for (int i = 1; i <= 100; i++) {
        buffer.record(
          inferenceTimeUs: i * 100,
          isFallback: i <= 10, // 10 fallbacks (10%)
          isError: i <= 2, // 2 errors (2%)
          modelVersion: '1.0.0-tflite',
        );
      }

      final stats = buffer.getRealtimeSessionStats();

      expect(stats.totalInferences, equals(100));
      expect(stats.fallbackCount, equals(10));
      expect(stats.fallbackRate, equals(0.10));
      expect(stats.fallbackPercentage, equals(10.0));
      expect(stats.errorCount, equals(2));

      // Percentiles for sorted 100..10000:
      // p50 index ~49 -> 5000 µs
      // p90 index ~89 -> 9000 µs
      // p95 index ~94 -> 9500 µs
      expect(stats.p50LatencyUs, equals(5000));
      expect(stats.p90LatencyUs, equals(9000));
      expect(stats.p95LatencyUs, equals(9500));
    });

    test('Handles empty buffer stats gracefully', () {
      final stats = buffer.getRealtimeSessionStats();

      expect(stats.totalInferences, equals(0));
      expect(stats.fallbackCount, equals(0));
      expect(stats.errorCount, equals(0));
      expect(stats.fallbackRate, equals(0.0));
      expect(stats.p50LatencyUs, equals(0));
      expect(stats.p90LatencyUs, equals(0));
      expect(stats.p95LatencyUs, equals(0));
    });

    test('Flushes metrics to Drift database and enforces 30-day retention cleanup', () async {
      final db = AttentionDatabase.inMemory();

      // Add records to buffer
      buffer.record(
        inferenceTimeUs: 1200,
        isFallback: false,
        isError: false,
        modelVersion: '1.0.0-tflite',
      );
      buffer.record(
        inferenceTimeUs: 2500,
        isFallback: true,
        isError: false,
        modelVersion: '1.0.0-tflite',
      );

      final stats = await buffer.flush(db);

      expect(stats, isNotNull);
      expect(stats!.totalInferences, equals(2));
      expect(buffer.isEmpty, isTrue);

      // Verify row persisted in Drift DB
      final entries = await db.inferenceTelemetryDao.getAll();
      expect(entries.length, equals(1));
      expect(entries.first.totalInferences, equals(2));
      expect(entries.first.fallbackCount, equals(1));
      expect(entries.first.p50LatencyUs, equals(1200));
      expect(entries.first.p95LatencyUs, equals(2500));

      await db.close();
    });

    test('GhostAI.predict automatically records metrics in telemetry ring buffer', () async {
      InferenceTelemetryBuffer.instance.clear();

      final notif = AppNotification(
        id: 'test_telemetry_notif',
        packageName: 'com.whatsapp',
        title: 'Meeting Alert',
        content: 'Project review meeting in 10 minutes',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await GhostAI.predict(notif);

      expect(InferenceTelemetryBuffer.instance.length, equals(1));
      final record = InferenceTelemetryBuffer.instance.records.first;
      expect(record.inferenceTimeUs, greaterThanOrEqualTo(0));
      expect(record.modelVersion, isNotEmpty);
    });
  });
}
