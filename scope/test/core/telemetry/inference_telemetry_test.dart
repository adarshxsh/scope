import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/telemetry/inference_telemetry.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InferenceTelemetryLog', () {
    test('toMap and fromMap preserve all telemetry fields', () {
      final log = InferenceTelemetryLog(
        id: 42,
        timestamp: 1700000000000,
        inferenceTimeUs: 1500,
        engineLatencyMs: 12,
        modelVersion: '1.0.0-tflite',
        engineVersion: '2.0.0-hybrid',
        isFallback: false,
        isError: false,
        errorMessage: null,
        notificationId: 'notif_123',
        category: 'finance',
      );

      final map = log.toMap();
      final roundTrip = InferenceTelemetryLog.fromMap(map);

      expect(roundTrip.id, equals(42));
      expect(roundTrip.timestamp, equals(1700000000000));
      expect(roundTrip.inferenceTimeUs, equals(1500));
      expect(roundTrip.engineLatencyMs, equals(12));
      expect(roundTrip.modelVersion, equals('1.0.0-tflite'));
      expect(roundTrip.engineVersion, equals('2.0.0-hybrid'));
      expect(roundTrip.isFallback, isFalse);
      expect(roundTrip.isError, isFalse);
      expect(roundTrip.notificationId, equals('notif_123'));
      expect(roundTrip.category, equals('finance'));
    });
  });

  group('InferenceTelemetryBuffer', () {
    test('handles empty buffer gracefully', () {
      final buffer = InferenceTelemetryBuffer();
      final stats = buffer.getStats();

      expect(stats.totalInferences, equals(0));
      expect(stats.avgInferenceTimeUs, equals(0.0));
      expect(stats.p95InferenceTimeUs, equals(0.0));
      expect(stats.fallbackCount, equals(0));
      expect(stats.fallbackRate, equals(0.0));
      expect(stats.failureCount, equals(0));
      expect(stats.failureRate, equals(0.0));
    });

    test('enforces maxCapacity bound', () {
      final buffer = InferenceTelemetryBuffer(maxCapacity: 5);

      for (int i = 1; i <= 10; i++) {
        buffer.record(InferenceTelemetryLog(
          timestamp: 1000 + i,
          inferenceTimeUs: i * 100,
          engineLatencyMs: i * 2,
          modelVersion: 'v1',
          engineVersion: 'v1',
        ));
      }

      final stats = buffer.getStats();
      expect(stats.totalInferences, equals(5));
      expect(stats.minInferenceTimeUs, equals(600));
      expect(stats.maxInferenceTimeUs, equals(1000));
    });

    test('accurately calculates latency averages, P95, fallback and failure rates', () {
      final buffer = InferenceTelemetryBuffer(maxCapacity: 100);

      // Record 10 items: times 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000
      for (int i = 1; i <= 10; i++) {
        buffer.record(InferenceTelemetryLog(
          timestamp: 1000 + i,
          inferenceTimeUs: i * 100,
          engineLatencyMs: 10,
          modelVersion: 'v1',
          engineVersion: 'v1',
          isFallback: i <= 2, // 2 fallbacks
          isError: i == 1,   // 1 error
        ));
      }

      final stats = buffer.getStats();
      expect(stats.totalInferences, equals(10));
      expect(stats.avgInferenceTimeUs, equals(550.0));
      expect(stats.minInferenceTimeUs, equals(100));
      expect(stats.maxInferenceTimeUs, equals(1000));
      expect(stats.fallbackCount, equals(2));
      expect(stats.fallbackRate, equals(0.2));
      expect(stats.failureCount, equals(1));
      expect(stats.failureRate, equals(0.1));
      expect(stats.p95InferenceTimeUs, equals(1000.0));
    });
  });

  group('InferenceTelemetryManager & Drift Database Persistence', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase.inMemory();
      InferenceTelemetryManager.instance.clear();
      InferenceTelemetryManager.instance.setDatabase(db);
    });

    tearDown(() async {
      await db.close();
      InferenceTelemetryManager.instance.clear();
      InferenceTelemetryManager.instance.setDatabase(null);
    });

    test('records telemetry to memory and persists to database', () async {
      await InferenceTelemetryManager.instance.recordInference(
        inferenceTimeUs: 2500,
        engineLatencyMs: 15,
        modelVersion: '1.0.0-tflite',
        engineVersion: '2.0.0-hybrid',
        isFallback: false,
        isError: false,
        notificationId: 'test_n1',
        category: 'msg',
      );

      final stats = InferenceTelemetryManager.instance.getStats();
      expect(stats.totalInferences, equals(1));
      expect(stats.avgInferenceTimeUs, equals(2500.0));

      final dbEntries = await db.inferenceTelemetryDao.getRecentTelemetry();
      expect(dbEntries.length, equals(1));
      expect(dbEntries.first.inferenceTimeUs, equals(2500));
      expect(dbEntries.first.engineLatencyMs, equals(15));
      expect(dbEntries.first.notificationId, equals('test_n1'));
      expect(dbEntries.first.category, equals('msg'));
    });

    test('GhostAnalysisEngine automatically logs telemetry on analyze', () async {
      final engine = GhostAnalysisEngine();
      final notif = AppNotification(
        id: 'telemetry_test_1',
        packageName: 'com.whatsapp',
        title: 'Security Code',
        content: 'Your code is 449201. Valid for 10 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await engine.analyze(notif);

      final stats = InferenceTelemetryManager.instance.getStats();
      expect(stats.totalInferences, greaterThanOrEqualTo(1));

      final dbEntries = await db.inferenceTelemetryDao.getRecentTelemetry();
      expect(dbEntries, isNotEmpty);
      expect(dbEntries.first.notificationId, equals('telemetry_test_1'));
    });
  });
}
