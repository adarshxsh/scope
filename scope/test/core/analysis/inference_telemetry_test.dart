import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/inference_telemetry.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelInferenceTelemetryTracker Unit Tests', () {
    late ModelInferenceTelemetryTracker tracker;

    setUp(() {
      tracker = ModelInferenceTelemetryTracker.withCapacity(10);
      tracker.clear();
    });

    test('records telemetry entries and computes statistical summaries', () {
      expect(tracker.count, equals(0));

      tracker.record(
        InferenceTelemetryRecord(
          id: '1',
          notificationId: 'notif_1',
          timestamp: DateTime.now(),
          featureExtractionUs: 1000,
          ruleEngineUs: 500,
          modelInferenceUs: 2000,
          totalPipelineUs: 3500,
          isModelLoaded: true,
          isFallbackUsed: false,
          predictedScore: 0.8,
          finalFusedScore: 0.8,
          resolvedPriority: 'high',
          classifiedCategory: 'msg',
          sanitizedPackage: 'com.whatsapp',
          status: 'success',
        ),
      );

      tracker.record(
        InferenceTelemetryRecord(
          id: '2',
          notificationId: 'notif_2',
          timestamp: DateTime.now(),
          featureExtractionUs: 1200,
          ruleEngineUs: 600,
          modelInferenceUs: 0,
          totalPipelineUs: 4000,
          isModelLoaded: false,
          isFallbackUsed: true,
          predictedScore: 0.5,
          finalFusedScore: 0.5,
          resolvedPriority: 'medium',
          classifiedCategory: 'sys',
          sanitizedPackage: 'com.example.app',
          status: 'fallback',
          errorLog: 'Model not loaded',
        ),
      );

      expect(tracker.count, equals(2));

      final summary = tracker.computeSummary();
      expect(summary.totalInferences, equals(2));
      expect(summary.avgTotalLatencyMs, equals(3.75));
      expect(summary.fallbackCount, equals(1));
      expect(summary.fallbackRatePercent, equals(50.0));
      expect(summary.modelSuccessRatePercent, equals(100.0));
      expect(tracker.auditLogs.length, equals(1));
      expect(tracker.auditLogs.first, contains('com.example.app'));
    });

    test('enforces bounded capacity limit to prevent memory leaks', () {
      final capacityTracker = ModelInferenceTelemetryTracker.withCapacity(5);

      for (int i = 0; i < 15; i++) {
        capacityTracker.record(
          InferenceTelemetryRecord(
            id: 'tel_$i',
            notificationId: 'notif_$i',
            timestamp: DateTime.now(),
            featureExtractionUs: 1000,
            ruleEngineUs: 500,
            modelInferenceUs: 2000,
            totalPipelineUs: 3500,
            isModelLoaded: true,
            isFallbackUsed: false,
            predictedScore: 0.9,
            finalFusedScore: 0.9,
            resolvedPriority: 'critical',
            classifiedCategory: 'finance',
            sanitizedPackage: 'com.bank',
            status: 'success',
          ),
        );
      }

      expect(capacityTracker.count, equals(5));
      expect(capacityTracker.records.first.id, equals('tel_10'));
      expect(capacityTracker.records.last.id, equals('tel_14'));
    });

    test('sanitizes package names and redacts PII', () {
      final clean1 = ModelInferenceTelemetryTracker.sanitizePackageName('com.whatsapp');
      final clean2 = ModelInferenceTelemetryTracker.sanitizePackageName('com.app?user=secret_token');
      final clean3 = ModelInferenceTelemetryTracker.sanitizePackageName('');

      expect(clean1, equals('com.whatsapp'));
      expect(clean2, equals('com.appusersecret_token'));
      expect(clean3, equals('unknown.app'));
    });

    test('records errors with stack trace details in audit log', () {
      tracker.recordError(
        notificationId: 'err_notif',
        packageName: 'com.bad.app',
        error: 'TFLite runtime segmentation fault',
        totalUs: 5000,
      );

      expect(tracker.count, equals(1));
      final rec = tracker.records.first;
      expect(rec.status, equals('error'));
      expect(rec.isFallbackUsed, isTrue);
      expect(rec.errorLog, contains('TFLite runtime segmentation fault'));
      expect(tracker.auditLogs.isNotEmpty, isTrue);
    });
  });

  group('GhostAI & GhostAnalysisEngine Telemetry Integration', () {
    setUp(() {
      ModelInferenceTelemetryTracker.instance.clear();
    });

    test('predicting notification in GhostAI records inference telemetry', () async {
      final notif = AppNotification(
        id: 'test_tel_1',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your OTP code is 991823. Valid for 10 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await GhostAI.predict(notif);

      expect(ModelInferenceTelemetryTracker.instance.count, greaterThanOrEqualTo(1));
      final lastRecord = ModelInferenceTelemetryTracker.instance.records.last;
      expect(lastRecord.notificationId, equals('test_tel_1'));
      expect(lastRecord.sanitizedPackage, equals('com.whatsapp'));
      expect(lastRecord.totalPipelineUs, greaterThan(0));
      expect(lastRecord.hasPiiRedacted, isTrue);
    });

    test('analyzing notification in GhostAnalysisEngine records telemetry', () async {
      final engine = GhostAnalysisEngine();
      const String sampleJson = '''
      {
        "version": "1.0",
        "rules": [
          {
            "id": "bank_debit",
            "category": "finance",
            "priority": "critical",
            "conditions": {
              "keywords": ["debited"]
            }
          }
        ]
      }
      ''';
      engine.ruleEngine.compile(sampleJson);

      final notif = AppNotification(
        id: 'test_engine_tel',
        packageName: 'com.example.bank',
        title: 'Debit Alert',
        content: 'Your account was debited Rs. 2000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await engine.analyze(notif);

      expect(ModelInferenceTelemetryTracker.instance.count, greaterThanOrEqualTo(1));
      final summary = ModelInferenceTelemetryTracker.instance.computeSummary();
      expect(summary.totalInferences, greaterThanOrEqualTo(1));
      expect(summary.avgTotalLatencyMs, greaterThan(0.0));
    });
  });
}
