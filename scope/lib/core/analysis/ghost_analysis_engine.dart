import 'package:flutter/services.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_evolution_trace.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/storage/inference_audit_logger.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;
  final InferenceAuditLogger? auditLogger;

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
    InferenceAuditLogger? auditLogger,
  })  : ruleEngine = ruleEngine ?? RuleEngine(),
        mlClassifier = mlClassifier ?? LiteRtClassifier(),
        auditLogger = auditLogger ?? InferenceAuditLogger();

  /// Compiles rules loaded from assets on engine startup.
  Future<void> initialize() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/rules.json');
      ruleEngine.compile(jsonStr);
      await ruleEngine.loadCustomRules();
    } catch (e) {
      // ignore: avoid_print
      print('GhostAnalysisEngine failed to load rules asset: $e');
    }
    try {
      await GhostAI.instance.initialize();
    } catch (e) {
      // ignore: avoid_print
      print('GhostAnalysisEngine failed to initialize GhostAI: $e');
    }
  }

  /// Executes the hybrid intelligence pipeline end-to-end.
  /// Intercepts raw notification data and resolves it into a fully decorated priority model.
  Future<AppNotification> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();

    // 0. Filter out progress/download/sync status notifications to prevent unnecessary analysis
    if (_isStatusOrProgressNotification(notification)) {
      stopwatch.stop();
      const statusOverrideTrigger = 'status_progress_filter';
      final statusTrace = ScoreEvolutionTrace(
        steps: const [
          ScoreEvolutionStep(
            stageName: 'Pre-Ingestion Status Filter',
            score: 0.0,
            description: 'Status/progress notification filtered prior to AI inference',
            trigger: statusOverrideTrigger,
          ),
        ],
        finalPriority: 'low',
        finalScore: 0.0,
        overrideTrigger: statusOverrideTrigger,
      );

      await auditLogger?.logInference(
        notificationId: notification.id,
        packageName: notification.packageName,
        timestamp: notification.timestamp,
        classifiedCategory: 'system_status',
        predictedScore: 0.0,
        fusedScore: 0.0,
        finalPriority: 'low',
        latencyMs: stopwatch.elapsedMilliseconds,
        overrideTrigger: statusOverrideTrigger,
        attributions: const [],
        scoreTrace: statusTrace,
        isFallback: false,
      );

      return notification.copyWith(
        priority: 'low',
        priorityScore: 0.0,
        classifiedCategory: 'system_status',
        explanation: 'Status or progress notification ignored by AI.',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: '2.0.0-hybrid',
      );
    }

    // 1. Structured Feature Extraction
    final features = FeatureExtractor.extract(
      title: notification.title,
      content: notification.content,
    );

    // 2. Rule Engine matching
    final ruleMatch = ruleEngine.match(notification);

    // 3. LiteRT Classification Category Inference
    final mlResult = await mlClassifier.analyze(notification);

    // 4. Score Fusion (hybrid conflict resolution or critical bypass triggers)
    final fusedResult = ScoreFusion.fuse(
      ruleResult: ruleMatch,
      modelResult: mlResult,
    );

    // Run unified look-again MLP model prediction
    final ghostResult = await GhostAI.predict(notification);

    // 5. Policy Engine (category + feature to priority levels resolution)
    final priority = PolicyEngine.resolvePriority(
      fusedResult: fusedResult,
      features: features,
      notification: notification,
      lookAgainScore: ghostResult.reviewScore,
    );

    // 6. Feature Attributions & Score Evolution Trace Calculation
    final attributions = FeatureAttributionCalculator.computeAttributions(
      notification: notification,
      features: features,
      predictedScore: ghostResult.predictedScore,
      matchedRuleId: ruleMatch?.ruleId,
    );

    final overrideTrigger = _determineOverrideTrigger(
      notification: notification,
      features: features,
      ghostResult: ghostResult,
      ruleMatch: ruleMatch,
    );

    final evolutionSteps = <ScoreEvolutionStep>[
      ScoreEvolutionStep(
        stageName: 'LiteRT Category Inference',
        score: mlResult.score,
        description: 'Inferred category "${mlResult.category}" via ${mlResult.engineName}',
      ),
      if (ruleMatch != null)
        ScoreEvolutionStep(
          stageName: 'Rule Engine Matching',
          score: ruleMatch.priority == 'critical' ? 1.0 : (ruleMatch.priority == 'high' ? 0.85 : 0.5),
          description: 'Matched rule "${ruleMatch.ruleId}" (${ruleMatch.priority.toUpperCase()})',
          ruleId: ruleMatch.ruleId,
        ),
      ScoreEvolutionStep(
        stageName: 'Score Fusion',
        score: fusedResult.score,
        description: fusedResult.isFallback ? 'Fallback heuristic score' : 'Fused model and rule score',
      ),
      ScoreEvolutionStep(
        stageName: 'Look-Again MLP Model',
        score: ghostResult.predictedScore,
        description: 'TFLite priority regression score',
      ),
      ScoreEvolutionStep(
        stageName: 'Policy Engine & Overrides',
        score: ghostResult.reviewScore,
        description: overrideTrigger != 'none' ? 'Override applied: $overrideTrigger' : 'Priority level $priority resolved',
        trigger: overrideTrigger,
      ),
    ];

    final scoreTrace = ScoreEvolutionTrace(
      steps: evolutionSteps,
      finalPriority: priority,
      finalScore: ghostResult.reviewScore,
      overrideTrigger: overrideTrigger,
    );

    // 7. Natural language explainability trace
    final explanation = ExplanationGenerator.generate(
      fusedResult: fusedResult,
      features: features,
      priority: priority,
      attributions: attributions,
      scoreTrace: scoreTrace,
    );

    stopwatch.stop();

    await auditLogger?.logInference(
      notificationId: notification.id,
      packageName: notification.packageName,
      timestamp: notification.timestamp,
      classifiedCategory: fusedResult.category,
      predictedScore: ghostResult.predictedScore,
      fusedScore: fusedResult.score,
      finalPriority: priority,
      latencyMs: stopwatch.elapsedMilliseconds,
      overrideTrigger: overrideTrigger,
      attributions: attributions,
      scoreTrace: scoreTrace,
      isFallback: fusedResult.isFallback,
    );

    return notification.copyWith(
      priority: priority,
      priorityScore: ghostResult.reviewScore,
      classifiedCategory: fusedResult.category,
      explanation: explanation,
      latencyMs: stopwatch.elapsedMilliseconds,
      ruleVersion: ruleEngine.version,
      modelVersion: GhostAI.instance.isModelLoaded ? '1.0.0-tflite' : 'fallback-heuristics',
      engineVersion: fusedResult.isFallback ? '2.0.0-hybrid (fallback)' : '2.0.0-hybrid',
      extractedFeatures: features.toMap(),
    );
  }

  String _determineOverrideTrigger({
    required AppNotification notification,
    required ExtractedFeatures features,
    required GhostAIResult ghostResult,
    MatchedRuleResult? ruleMatch,
  }) {
    if (ghostResult.reviewScore == 0.0 && ghostResult.predictedScore > 0.0) {
      if (features.otp != null || notification.content.toLowerCase().contains('otp') || notification.content.toLowerCase().contains('valid for')) {
        return 'expired_otp';
      }
      if (features.hasDeadline) {
        return 'expired_reminder';
      }
      final lowerTitle = notification.title.toLowerCase();
      final lowerContent = notification.content.toLowerCase();
      if (lowerTitle.contains('completed') || lowerContent.contains('completed') || lowerTitle.contains('done')) {
        return 'completed_task_suppression';
      }
      return 'duplicate_suppression';
    }
    if (ruleMatch != null &&
        (ruleMatch.priority == 'critical' ||
            ruleMatch.ruleId == 'otp_security' ||
            ruleMatch.ruleId == 'finance_debit' ||
            ruleMatch.ruleId == 'scholarship_portal')) {
      return 'critical_bypass';
    }
    return 'none';
  }

  bool _isStatusOrProgressNotification(AppNotification notification) {
    if (notification.category == 'progress' || notification.category == 'status') {
      return true;
    }

    final lowerTitle = notification.title.toLowerCase();
    final lowerContent = notification.content.toLowerCase();
    final combined = '$lowerTitle $lowerContent';

    final progressKeywords = [
      'downloading',
      'uploading',
      'sending file',
      'receiving file',
      'syncing',
      'backing up',
      'file transfer',
    ];

    for (final keyword in progressKeywords) {
      if (combined.contains(keyword)) {
        return true;
      }
    }

    return false;
  }
}
