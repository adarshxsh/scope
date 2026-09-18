import 'package:flutter/services.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/guardrails/ingestion_guardrails.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;
  final IngestionGuardrailService guardrailService;

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
    IngestionGuardrailService? guardrailService,
  })  : ruleEngine = ruleEngine ?? RuleEngine(),
        mlClassifier = mlClassifier ?? LiteRtClassifier(),
        guardrailService = guardrailService ?? IngestionGuardrailService();

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
      final policyJson = await rootBundle.loadString('assets/ingestion_policy.json');
      guardrailService.updatePolicy(IngestionPolicy.fromJson(policyJson));
    } catch (_) {
      // Keep default ingestion policy on error
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

    // 0. Pre-ingestion guardrail evaluation & string truncation
    final guardrailResult = guardrailService.evaluate(notification);
    if (!guardrailResult.isAllowed) {
      stopwatch.stop();
      return notification.copyWith(
        priority: 'low',
        priorityScore: 0.0,
        classifiedCategory: 'system_status',
        explanation: 'Notification blocked by ingestion guardrails (${guardrailResult.dropReason ?? 'unknown'}).',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: '2.0.0-hybrid',
      );
    }

    final targetNotif = guardrailResult.sanitizedNotification;

    // Filter out progress/download/sync status notifications to prevent unnecessary analysis
    if (_isStatusOrProgressNotification(targetNotif)) {
      stopwatch.stop();
      return targetNotif.copyWith(
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
      title: targetNotif.title,
      content: targetNotif.content,
    );

    // 2. Rule Engine matching
    final ruleMatch = ruleEngine.match(targetNotif);

    // 3. LiteRT Classification Category Inference
    final mlResult = await mlClassifier.analyze(targetNotif);

    // 4. Score Fusion (hybrid conflict resolution or critical bypass triggers)
    final fusedResult = ScoreFusion.fuse(
      ruleResult: ruleMatch,
      modelResult: mlResult,
    );

    // Run unified look-again MLP model prediction
    final ghostResult = await GhostAI.predict(targetNotif);

    // 5. Policy Engine (category + feature to priority levels resolution)
    final priority = PolicyEngine.resolvePriority(
      fusedResult: fusedResult,
      features: features,
      notification: targetNotif,
      lookAgainScore: ghostResult.reviewScore,
    );

    // 6. Natural language explainability trace
    final explanation = ExplanationGenerator.generate(
      fusedResult: fusedResult,
      features: features,
      priority: priority,
    );

    stopwatch.stop();

    return targetNotif.copyWith(
      priority: priority,
      priorityScore: ghostResult.reviewScore,
      classifiedCategory: fusedResult.category,
      explanation: explanation,
      latencyMs: stopwatch.elapsedMilliseconds,
      ruleVersion: ruleEngine.version,
      modelVersion: GhostAI.instance.isModelLoaded ? '1.0.0-tflite' : 'fallback-heuristics',
      engineVersion: '2.0.0-hybrid',
      extractedFeatures: features.toMap(),
    );
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
