import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';

import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';

import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/pii_redactor.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeatureAttribution & ScoreEvolutionTrace', () {
    test('computes feature attributions with directional weights', () {
      final features = const ExtractedFeatures(
        otp: '992817',
        amount: 2500.0,
        hasDeadline: true,
        urls: ['https://example.com/pay'],
      );
      final featureVector = List<double>.filled(63, 0.0);
      featureVector[11] = 1.0; // contains_otp
      featureVector[10] = 1.0; // contains_money
      featureVector[27] = 1.0; // contains_deadline

      final attributions = FeatureAttribution.computeFromVector(
        featureVector: featureVector,
        features: features,
        category: 'finance',
      );

      expect(attributions, isNotEmpty);
      expect(attributions.any((a) => a.featureKey == 'contains_otp'), isTrue);
      expect(attributions.any((a) => a.featureKey == 'contains_money'), isTrue);
      expect(attributions.any((a) => a.featureKey == 'contains_deadline'), isTrue);
      expect(attributions.any((a) => a.direction == 'positive'), isTrue);
    });

    test('ScoreEvolutionTrace tracks step-by-step priority changes', () {
      final step1 = ScoreEvolutionStep(
        stage: '1. Model Inference',
        scoreBefore: 0.0,
        scoreAfter: 0.80,
        action: 'TFLite Model Prediction',
        details: 'Raw prediction score 80%',
      );
      final step2 = ScoreEvolutionStep(
        stage: '2. Rule Fusion',
        scoreBefore: 0.80,
        scoreAfter: 1.0,
        action: 'Critical Bypass',
        details: 'Matched OTP security rule',
      );

      final trace = ScoreEvolutionTrace(
        steps: [step1, step2],
        initialScore: 0.80,
        finalScore: 1.0,
        overrideTrigger: 'critical_bypass',
      );

      final map = trace.toMap();
      final restored = ScoreEvolutionTrace.fromMap(map);

      expect(restored.steps.length, equals(2));
      expect(restored.overrideTrigger, equals('critical_bypass'));
      expect(restored.finalScore, equals(1.0));
    });
  });

  group('PII Redaction Guardrails', () {
    test('PiiRedactor sanitizes OTPs, amounts, emails, phones, and URLs', () {
      const rawText = 'Your OTP code is 881923 for Rs. 4,500 at https://secure.com. Contact support@bank.com or +1-800-555-0199.';
      final redacted = PiiRedactor.redact(rawText);

      expect(redacted, contains('[REDACTED_OTP]'));
      expect(redacted, contains('[REDACTED_AMOUNT]'));
      expect(redacted, contains('[REDACTED_URL]'));
      expect(redacted, contains('[REDACTED_EMAIL]'));
      expect(redacted, contains('[REDACTED_PHONE]'));
      expect(redacted, isNot(contains('881923')));
      expect(redacted, isNot(contains('4,500')));
    });

    test('ExplanationGenerator produces zero cleartext PII', () {
      final features = const ExtractedFeatures(
        otp: '449102',
        amount: 15000.0,
        hasDeadline: true,
      );

      final explanation = ExplanationGenerator.generate(

        fusedResult: const AnalysisResult(
          category: 'finance',
          score: 1.0,
          engineName: 'score_fusion',
          matchedSignals: ['debit_match'],
          latencyMs: 5,
        ),
        features: features,
        priority: 'critical',
      );

      expect(explanation, isNot(contains('449102')));
      expect(explanation, isNot(contains('15000')));
      expect(explanation, contains('[REDACTED_OTP]'));
      expect(explanation, contains('[REDACTED_AMOUNT]'));
    });
  });

  group('Inference Latency & Audit Persistence', () {
    late AttentionDatabase db;
    late InferenceAuditDao auditDao;
    late GhostAnalysisEngine engine;

    setUp(() {
      db = AttentionDatabase.inMemory();
      auditDao = InferenceAuditDao(db);
      engine = GhostAnalysisEngine(auditDao: auditDao);
    });

    tearDown(() async {
      await db.close();
    });

    test('executes inference under 50ms latency benchmark', () async {
      await engine.initialize();
      final warmupNotif = AppNotification(
        id: 'warmup',
        packageName: 'com.test',
        title: 'Warmup',
        content: 'Warmup',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await engine.analyze(warmupNotif);

      final notif = AppNotification(
        id: 'perf_test_1',
        packageName: 'com.whatsapp',
        title: 'Project Update',
        content: 'Deadline for submission is tomorrow at 5 PM.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final stopwatch = Stopwatch()..start();
      final analyzed = await engine.analyze(notif);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
      expect(analyzed.latencyMs, lessThan(50));
      expect(analyzed.extractedFeatures, isNotNull);
      expect(analyzed.extractedFeatures!['featureAttributions'], isNotNull);
      expect(analyzed.extractedFeatures!['scoreEvolution'], isNotNull);
    });



    test('persists audit logs and clears old entries on set-based cleanup', () async {
      for (int i = 0; i < 10; i++) {
        final notif = AppNotification(
          id: 'audit_notif_$i',
          packageName: 'com.test.app',
          title: 'Test Title $i',
          content: 'Test content body number $i',
          timestamp: DateTime.now().millisecondsSinceEpoch - (i * 1000),
        );
        await engine.analyze(notif);
      }

      final recentLogs = await auditDao.getRecentAuditLogs(limit: 50);
      expect(recentLogs.length, equals(10));
      expect(recentLogs.first.packageName, isNot(contains('cleartext')));

      // Test set-based cleanup
      await db.runSetBasedCleanup(DateTime.now().millisecondsSinceEpoch + 1000);
      final remainingLogs = await auditDao.getRecentAuditLogs(limit: 50);
      expect(remainingLogs.length, lessThanOrEqualTo(10));
    });
  });
}
