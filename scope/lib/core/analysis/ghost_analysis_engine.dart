import 'package:flutter/services.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/utils/privacy_logger.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;

  /// In-memory LRU cache of analyzed notifications to prevent redundant ML inference.
  final Map<String, AppNotification> _analysisCache = {};
  static const int _maxCacheSize = 200;

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

  /// Clears the in-memory analysis cache.
  void clearCache() {
    _analysisCache.clear();
  }

  /// Executes the hybrid intelligence pipeline end-to-end.
  /// Intercepts raw notification data and resolves it into a fully decorated priority model.
  Future<AppNotification> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();

    final cacheKey = notification.id.isNotEmpty
        ? notification.id
        : AppNotification.generateStableId(
            packageName: notification.packageName,
            timestamp: notification.timestamp,
            title: notification.title,
            content: notification.content,
          );

    // Return cached result if available to avoid redundant ML inference
    if (_analysisCache.containsKey(cacheKey)) {
      final cached = _analysisCache[cacheKey]!;
      stopwatch.stop();
      PrivacyLogger.logInference(
        packageName: cached.packageName,
        latencyMs: stopwatch.elapsedMilliseconds,
        priority: cached.priority ?? 'medium',
        category: cached.classifiedCategory ?? 'unknown',
        cacheHit: true,
      );
      return cached.copyWith(latencyMs: stopwatch.elapsedMilliseconds);
    }

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
      _cacheResult(cacheKey, statusResult);
      return statusResult;
    }

    try {
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

      PrivacyLogger.logInference(
        packageName: result.packageName,
        latencyMs: stopwatch.elapsedMilliseconds,
        priority: result.priority ?? 'medium',
        category: result.classifiedCategory ?? 'unknown',
        cacheHit: false,
      );

      _cacheResult(cacheKey, result);
      return result;
    } catch (e, stack) {
      stopwatch.stop();
      PrivacyLogger.logError('GhostAnalysisEngine.analyze', e, stack);

      final fallbackResult = notification.copyWith(
        priority: notification.priority ?? 'medium',
        priorityScore: 0.50,
        classifiedCategory: notification.classifiedCategory ?? 'uncategorized',
        explanation: 'Fallback analysis due to exception.',
        latencyMs: stopwatch.elapsedMilliseconds,
        engineVersion: '2.0.0-fallback',
      );

      _cacheResult(cacheKey, fallbackResult);
      return fallbackResult;
    }
  }

  void _cacheResult(String key, AppNotification result) {
    if (key.isNotEmpty) {
      if (_analysisCache.length >= _maxCacheSize) {
        _analysisCache.remove(_analysisCache.keys.first);
      }
      _analysisCache[key] = result;
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
