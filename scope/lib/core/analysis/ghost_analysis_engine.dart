import 'package:flutter/services.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/state/resource_state_controller.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;
  final ResourceStateController resourceController;

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
    ResourceStateController? resourceController,
  })  : ruleEngine = ruleEngine ?? RuleEngine(),
        mlClassifier = mlClassifier ?? LiteRtClassifier(),
        resourceController = resourceController ?? ResourceStateController.instance;

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

    // Check device thermal/battery status
    final bool isThermalFallback = resourceController.shouldBypassTFLite;

    // 0. Filter out progress/download/sync status notifications to prevent unnecessary analysis
    if (_isStatusOrProgressNotification(notification)) {
      stopwatch.stop();
      return notification.copyWith(
        priority: 'low',
        priorityScore: 0.0,
        classifiedCategory: 'system_status',
        explanation: 'Status or progress notification ignored by AI.',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: isThermalFallback ? '2.0.0-hybrid (thermal-fallback)' : '2.0.0-hybrid',
      );
    }

    // 1. Structured Feature Extraction
    final features = FeatureExtractor.extract(
      title: notification.title,
      content: notification.content,
    );

    // 2. Rule Engine matching
    final ruleMatch = ruleEngine.match(notification);

    // 3. LiteRT Classification Category Inference (bypassed under resource pressure)
    final mlResult = await mlClassifier.analyze(
      notification,
      bypassTFLite: isThermalFallback,
    );

    // 4. Score Fusion (hybrid conflict resolution or critical bypass triggers)
    final fusedResult = ScoreFusion.fuse(
      ruleResult: ruleMatch,
      modelResult: mlResult,
    );

    // Run unified look-again MLP model prediction (bypassed under resource pressure)
    final ghostResult = await GhostAI.predict(
      notification,
      bypassTFLite: isThermalFallback,
    );

    // 5. Policy Engine (category + feature to priority levels resolution)
    final priority = PolicyEngine.resolvePriority(
      fusedResult: fusedResult,
      features: features,
      notification: notification,
      lookAgainScore: ghostResult.reviewScore,
    );

    // 6. Natural language explainability trace
    final rawExplanation = ExplanationGenerator.generate(
      fusedResult: fusedResult,
      features: features,
      priority: priority,
    );
    final explanation = isThermalFallback
        ? 'Thermal/Battery guardrail active. Fast-path heuristic fallback triggered. $rawExplanation'
        : rawExplanation;

    stopwatch.stop();

    final String engineVersion = isThermalFallback
        ? '2.0.0-hybrid (thermal-fallback)'
        : (fusedResult.isFallback ? '2.0.0-hybrid (fallback)' : '2.0.0-hybrid');

    final String modelVersion = isThermalFallback
        ? 'thermal-save-heuristic-fallback'
        : (GhostAI.instance.isModelLoaded ? '1.0.0-tflite' : 'fallback-heuristics');

    return notification.copyWith(
      priority: priority,
      priorityScore: ghostResult.reviewScore,
      classifiedCategory: fusedResult.category,
      explanation: explanation,
      latencyMs: stopwatch.elapsedMilliseconds,
      ruleVersion: ruleEngine.version,
      modelVersion: modelVersion,
      engineVersion: engineVersion,
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
