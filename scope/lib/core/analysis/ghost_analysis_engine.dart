import 'package:flutter/services.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/inference_telemetry.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
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

    try {
      // 0. Filter out progress/download/sync status notifications to prevent unnecessary analysis
      if (_isStatusOrProgressNotification(notification)) {
        stopwatch.stop();
        ModelInferenceTelemetryTracker.instance.record(
          InferenceTelemetryRecord(
            id: 'tel_${DateTime.now().microsecondsSinceEpoch}',
            notificationId: notification.id,
            timestamp: DateTime.now(),
            featureExtractionUs: 0,
            ruleEngineUs: 0,
            modelInferenceUs: 0,
            totalPipelineUs: stopwatch.elapsedMicroseconds,
            isModelLoaded: GhostAI.instance.isModelLoaded,
            isFallbackUsed: false,
            predictedScore: 0.0,
            finalFusedScore: 0.0,
            resolvedPriority: 'low',
            classifiedCategory: 'system_status',
            ruleVersion: ruleEngine.version,
            modelVersion: GhostAI.instance.isModelLoaded ? '1.0.0-tflite' : 'fallback-heuristics',
            sanitizedPackage: ModelInferenceTelemetryTracker.sanitizePackageName(notification.packageName),
            hasPiiRedacted: true,
            status: 'success',
            errorLog: 'Filtered as progress/status notification',
          ),
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

      // 6. Natural language explainability trace
      final explanation = ExplanationGenerator.generate(
        fusedResult: fusedResult,
        features: features,
        priority: priority,
      );

      stopwatch.stop();

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
    } catch (e) {
      stopwatch.stop();
      ModelInferenceTelemetryTracker.instance.recordError(
        notificationId: notification.id,
        packageName: notification.packageName,
        error: 'GhostAnalysisEngine exception: $e',
        totalUs: stopwatch.elapsedMicroseconds,
      );
      return notification.copyWith(
        priority: 'medium',
        priorityScore: 0.5,
        classifiedCategory: 'general',
        explanation: 'Fallback priority assigned due to analysis error.',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: '2.0.0-fallback',
      );
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
