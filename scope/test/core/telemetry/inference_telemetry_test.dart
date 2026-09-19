import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/telemetry/inference_telemetry.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InferenceTelemetryRecord & Sanitization', () {
    test('sanitizes categories and enforces boundary constraints', () {
      final record = InferenceTelemetryRecord(
        inferenceTimeUs: -50,
        totalLatencyMs: -10,
        modelVersion: r'1.0.0-tflite!@#$',
        classifiedCategory: '  FINANCE!!! Secret Text 123  ',
      );

      expect(record.inferenceTimeUs, equals(0));
      expect(record.totalLatencyMs, equals(0));
      expect(record.modelVersion, equals('1.0.0-tflite'));
      expect(record.classifiedCategory, equals('financesecrettext123'));
    });

    test('serializes to and from map cleanly without leaking PII', () {
      final record = InferenceTelemetryRecord(
        inferenceTimeUs: 12000,
        totalLatencyMs: 15,
        isFallback: false,
        isSuccess: true,
        modelVersion: '1.0.0-tflite',
        classifiedCategory: 'promo',
      );

      final map = record.toMap();
      expect(map.containsKey('title'), isFalse);
      expect(map.containsKey('content'), isFalse);

      final restored = InferenceTelemetryRecord.fromMap(map);
      expect(restored.inferenceTimeUs, equals(12000));
      expect(restored.totalLatencyMs, equals(15));
      expect(restored.isFallback, isFalse);
      expect(restored.isSuccess, isTrue);
      expect(restored.modelVersion, equals('1.0.0-tflite'));
      expect(restored.classifiedCategory, equals('promo'));
    });
  });

  group('InferenceTelemetryBuffer', () {
    test('enforces bounded capacity limit of 500 items', () {
      final buffer = InferenceTelemetryBuffer(maxCapacity: 500);

      for (int i = 0; i < 600; i++) {
        buffer.record(InferenceTelemetryRecord(
          inferenceTimeUs: 1000 + i,
          totalLatencyMs: 5,
          modelVersion: '1.0.0-tflite',
          classifiedCategory: 'msg',
        ));
      }

      expect(buffer.records.length, equals(500));
      // First item recorded should now be index 100 (due to FIFO eviction)
      expect(buffer.records.first.inferenceTimeUs, equals(1100));
      expect(buffer.records.last.inferenceTimeUs, equals(1599));
    });

    test('computes aggregated metrics correctly including P95 and fallback rate', () {
      final buffer = InferenceTelemetryBuffer(maxCapacity: 100);

      for (int i = 1; i <= 100; i++) {
        buffer.record(InferenceTelemetryRecord(
          inferenceTimeUs: i * 100, // 100 us to 10000 us
          totalLatencyMs: i,
          isFallback: i % 10 == 0, // 10 fallbacks out of 100
          isSuccess: i != 50, // 1 failure
          modelVersion: '1.0.0-tflite',
          classifiedCategory: 'sys',
        ));
      }

      final metrics = buffer.getMetrics();
      expect(metrics.totalInferences, equals(100));
      expect(metrics.averageInferenceTimeUs, equals(5050.0));
      expect(metrics.averageTotalLatencyMs, equals(50.5));
      expect(metrics.fallbackCount, equals(10));
      expect(metrics.fallbackRate, equals(0.10));
      expect(metrics.failureCount, equals(1));
      expect(metrics.p95InferenceTimeUs, equals(9500.0));
    });
  });

  group('GhostAnalysisEngine Telemetry Integration', () {
    test('records telemetry during analysis and meets sub-50ms latency benchmark', () async {
      final buffer = InferenceTelemetryBuffer();
      final engine = GhostAnalysisEngine(telemetryBuffer: buffer);
      await engine.initialize();

      final notif = AppNotification(
        id: 'tel_1',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your OTP security code is 492011.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final stopwatch = Stopwatch()..start();
      final result = await engine.analyze(notif);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
      expect(result.priority, equals('critical'));
      expect(buffer.records.length, equals(1));

      final rec = buffer.records.first;
      expect(rec.isSuccess, isTrue);
      expect(rec.classifiedCategory, isNotNull);
      expect(rec.totalLatencyMs, lessThanOrEqualTo(50));
    });

    test('recovers gracefully and records failure telemetry when pipeline errors occur', () async {
      final buffer = InferenceTelemetryBuffer();
      final engine = GhostAnalysisEngine(telemetryBuffer: buffer);

      // Force error on bad inputs or uninitialized state
      final notif = AppNotification(
        id: 'err_1',
        packageName: 'com.test',
        title: 'Test Title',
        content: 'Test Content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await engine.analyze(notif);

      expect(result.priority, isNotNull);
      expect(buffer.records.length, equals(1));
      expect(buffer.records.first.isFallback, isTrue);
    });
  });

  group('Drift Database Telemetry Persistence & FIFO Capping', () {
    test('persists telemetry records and caps database rows to 500 max', () async {
      final db = AttentionDatabase.inMemory();

      for (int i = 0; i < 550; i++) {
        await db.inferenceTelemetryDao.insertRecord(InferenceTelemetryEntry(
          id: 0,
          timestamp: 1000000 + i,
          inferenceTimeUs: 2000,
          totalLatencyMs: 12,
          isFallback: false,
          isSuccess: true,
          modelVersion: '1.0.0-tflite',
          classifiedCategory: 'finance',
        ));
      }

      final rows = await db.inferenceTelemetryDao.getAll();
      expect(rows.length, equals(500));
      // Primary timestamp ordering: newest first
      expect(rows.first.timestamp, equals(1000549));
      expect(rows.last.timestamp, equals(1000050));

      await db.close();
    });
  });
}
