import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/analysis/score_evolution_trace.dart';
import 'package:scope/core/storage/inference_audit_logger.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('InferenceAuditLogger Tests', () {
    test('logs and retrieves audit entries in memory', () async {
      final logger = InferenceAuditLogger();

      await logger.logInference(
        notificationId: 'notif_100',
        packageName: 'com.whatsapp',
        timestamp: 1600000000000,
        classifiedCategory: 'msg',
        predictedScore: 0.95,
        fusedScore: 0.95,
        finalPriority: 'critical',
        latencyMs: 12,
        overrideTrigger: 'none',
        attributions: const [
          FeatureAttribution(
            featureKey: 'contains_otp',
            featureName: 'Security Code',
            influence: 0.65,
            impact: 'positive',
            description: 'OTP code detected',
          )
        ],
        scoreTrace: const ScoreEvolutionTrace(
          steps: [
            ScoreEvolutionStep(
              stageName: 'LiteRT Category',
              score: 0.95,
              description: 'Inferred msg category',
            )
          ],
          finalPriority: 'critical',
          finalScore: 0.95,
        ),
      );

      final entry = await logger.getAuditLogForNotification('notif_100');
      expect(entry, isNotNull);
      expect(entry!.notificationId, equals('notif_100'));
      expect(entry.packageName, equals('com.whatsapp'));
      expect(entry.finalPriority, equals('critical'));

      final allLogs = await logger.getAllLogs();
      expect(allLogs, isNotEmpty);
    });

    test('logs and retrieves audit entries from in-memory Drift database', () async {
      final db = AttentionDatabase.inMemory();
      final logger = InferenceAuditLogger.fromDatabase(db);

      await logger.logInference(
        notificationId: 'notif_200',
        packageName: 'com.bank',
        timestamp: 1600000000000,
        classifiedCategory: 'finance',
        predictedScore: 0.85,
        fusedScore: 0.85,
        finalPriority: 'high',
        latencyMs: 15,
        overrideTrigger: 'none',
        attributions: const [],
        scoreTrace: const ScoreEvolutionTrace(
          steps: [],
          finalPriority: 'high',
          finalScore: 0.85,
        ),
      );

      final entry = await logger.getAuditLogForNotification('notif_200');
      expect(entry, isNotNull);
      expect(entry!.notificationId, equals('notif_200'));
      expect(entry.classifiedCategory, equals('finance'));

      await db.close();
    });
  });
}
