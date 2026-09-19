import 'package:flutter/services.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/telemetry/telemetry_governance_service.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;
  final InferenceTelemetryDao? telemetryDao;

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
    this.telemetryDao,
  })  : ruleEngine = ruleEngine ?? RuleEngine(),
        mlClassifier = mlClassifier ?? LiteRtClassifier();

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
      final statusResult = notification.copyWith(
        priority: 'low',
        priorityScore: 0.0,
        classifiedCategory: 'system_status',
        explanation: 'Status or progress notification ignored by AI.',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: '2.0.0-hybrid',
      );
      await _logTelemetry(statusResult, isFallback: false);
      return statusResult;
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

    // 6. Natural language explainability trace
    final explanation = ExplanationGenerator.generate(
      fusedResult: fusedResult,
      features: features,
      priority: priority,
    );

    stopwatch.stop();

    final result = notification.copyWith(
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

    await _logTelemetry(result, isFallback: mlResult.isFallback);

    return result;
  }

  Future<void> _logTelemetry(AppNotification notification, {required bool isFallback}) async {
    if (telemetryDao == null) return;
    try {
      final notifTimestamp = notification.timestamp > 0
          ? notification.timestamp
          : DateTime.now().millisecondsSinceEpoch;
      final quantizedTime = TelemetryGovernanceService.quantizeTimestamp(notifTimestamp);

      await telemetryDao!.insertTelemetry(
        InferenceTelemetryEntry(
          id: 0,
          notificationId: notification.id,
          quantizedTimestamp: quantizedTime,
          latencyMs: notification.latencyMs ?? 0,
          modelVersion: notification.modelVersion,
          ruleVersion: notification.ruleVersion,
          engineVersion: notification.engineVersion,
          isFallback: isFallback,
          priorityScore: notification.priorityScore ?? 0.0,
          priorityLevel: notification.priority,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      // Fallback error recovery path
      // ignore: avoid_print
      print('GhostAnalysisEngine failed to log telemetry: $e');
    }
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
