import 'package:flutter/services.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/telemetry/inference_telemetry.dart';
import 'package:scope/database/attention_database.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;
  final InferenceTelemetryBuffer telemetryBuffer;
  final AttentionDatabase? database;

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
    InferenceTelemetryBuffer? telemetryBuffer,
    this.database,
  })  : ruleEngine = ruleEngine ?? RuleEngine(),
        mlClassifier = mlClassifier ?? LiteRtClassifier(),
        telemetryBuffer = telemetryBuffer ?? InferenceTelemetryBuffer.instance;

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
        final result = notification.copyWith(
          priority: 'low',
          priorityScore: 0.0,
          classifiedCategory: 'system_status',
          explanation: 'Status or progress notification ignored by AI.',
          latencyMs: stopwatch.elapsedMilliseconds,
          engineVersion: '2.0.0-hybrid',
        );

        _recordTelemetry(
          inferenceTimeUs: 0,
          totalLatencyMs: stopwatch.elapsedMilliseconds,
          isFallback: true,
          isSuccess: true,
          modelVersion: 'system_filter',
          classifiedCategory: 'system_status',
        );

        return result;
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

      final modelVer = GhostAI.instance.isModelLoaded ? '1.0.0-tflite' : 'fallback-heuristics';
      final isFallback = ghostResult.isFallback || !GhostAI.instance.isModelLoaded;

      _recordTelemetry(
        inferenceTimeUs: ghostResult.inferenceTimeUs,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
        isFallback: isFallback,
        isSuccess: ghostResult.isSuccess,
        modelVersion: modelVer,
        classifiedCategory: fusedResult.category,
      );

      return notification.copyWith(
        priority: priority,
        priorityScore: ghostResult.reviewScore,
        classifiedCategory: fusedResult.category,
        explanation: explanation,
        latencyMs: stopwatch.elapsedMilliseconds,
        ruleVersion: ruleEngine.version,
        modelVersion: modelVer,
        engineVersion: fusedResult.isFallback ? '2.0.0-hybrid (fallback)' : '2.0.0-hybrid',
        extractedFeatures: features.toMap(),
      );
    } catch (e) {
      stopwatch.stop();
      _recordTelemetry(
        inferenceTimeUs: 0,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
        isFallback: true,
        isSuccess: false,
        modelVersion: 'fallback-heuristics',
        classifiedCategory: 'error_fallback',
      );

      return notification.copyWith(
        priority: 'medium',
        priorityScore: 0.50,
        classifiedCategory: 'error_fallback',
        explanation: 'Pipeline error occurred; recovered gracefully with fallback.',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: '2.0.0-hybrid',
      );
    }
  }

  void _recordTelemetry({
    required int inferenceTimeUs,
    required int totalLatencyMs,
    required bool isFallback,
    required bool isSuccess,
    required String modelVersion,
    String? classifiedCategory,
  }) {
    final record = InferenceTelemetryRecord(
      inferenceTimeUs: inferenceTimeUs,
      totalLatencyMs: totalLatencyMs,
      isFallback: isFallback,
      isSuccess: isSuccess,
      modelVersion: modelVersion,
      classifiedCategory: classifiedCategory,
    );

    telemetryBuffer.record(record);

    if (database != null) {
      try {
        database!.inferenceTelemetryDao.insertRecord(InferenceTelemetryEntry(
          id: 0,
          timestamp: record.timestamp,
          inferenceTimeUs: record.inferenceTimeUs,
          totalLatencyMs: record.totalLatencyMs,
          isFallback: record.isFallback,
          isSuccess: record.isSuccess,
          modelVersion: record.modelVersion,
          classifiedCategory: record.classifiedCategory,
        ));
      } catch (_) {
        // Silently recover if DB write fails
      }
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
