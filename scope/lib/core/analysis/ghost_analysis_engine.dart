import 'package:flutter/services.dart';
import 'package:scope/core/analysis/explainability_engine.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// The central hub of Ghost AI coordinating all classification stages.
class GhostAnalysisEngine {
  final RuleEngine ruleEngine;
  final LiteRtClassifier mlClassifier;
  final InferenceAuditLogDao? auditLogDao;

  static final Map<String, InferenceAuditLogEntry> _inMemoryAuditLogs = {};

  GhostAnalysisEngine({
    RuleEngine? ruleEngine,
    LiteRtClassifier? mlClassifier,
    InferenceAuditLogDao? auditLogDao,
    AttentionDatabase? db,
  })  : ruleEngine = ruleEngine ?? RuleEngine(),
        mlClassifier = mlClassifier ?? LiteRtClassifier(),
        auditLogDao = auditLogDao ?? (db != null ? InferenceAuditLogDao(db) : null);

  /// Retrieves an audit log entry for a notification ID (checking in-memory cache first, then DB).
  Future<InferenceAuditLogEntry?> getAuditLog(String notificationId) async {
    if (_inMemoryAuditLogs.containsKey(notificationId)) {
      return _inMemoryAuditLogs[notificationId];
    }
    if (auditLogDao != null) {
      return await auditLogDao!.getAuditLogForNotification(notificationId);
    }
    return null;
  }

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
      final latencyMs = stopwatch.elapsedMilliseconds;
      final statusAuditEntry = InferenceAuditLogEntry(
        id: 'audit_${notification.id}_${DateTime.now().millisecondsSinceEpoch}',
        notificationId: notification.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        rawModelScore: 0.0,
        ruleMatchScore: 0.0,
        fusedScore: 0.0,
        finalScore: 0.0,
        overrideTriggers: 'status_notification_ignored',
        topFeatureAttributions: {'status_ignored': -1.0},
        inputFeatureVector: {},
        latencyMs: latencyMs,
      );
      _inMemoryAuditLogs[notification.id] = statusAuditEntry;
      if (auditLogDao != null) {
        try {
          await auditLogDao!.insertAuditLog(statusAuditEntry);
        } catch (e) {
          // ignore error in headless/test environments without DB
        }
      }

      return notification.copyWith(
        priority: 'low',
        priorityScore: 0.0,
        classifiedCategory: 'system_status',
        explanation: 'Status or progress notification ignored by AI.',
        latencyMs: latencyMs,
        engineVersion: '2.0.0-hybrid',
      );
    }

    // 1. Structured Feature Extraction
    final features = FeatureExtractor.extract(
      title: notification.title,
      content: notification.content,
    );
    final featureVector = FeatureExtractor.extractFromAppNotification(notification);

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
    final policyResult = PolicyEngine.resolvePriorityDetails(
      fusedResult: fusedResult,
      features: features,
      notification: notification,
      lookAgainScore: ghostResult.reviewScore,
    );
    final priority = policyResult.priority;

    // Collect all override triggers (policy engine + GhostAI overrides)
    final overrideTriggers = List<String>.from(policyResult.overrideTriggers);

    // Check GhostAI overrides
    final hasOtp = featureVector[11] == 1.0;
    final hasDeadline = featureVector[27] == 1.0;
    if (hasOtp && _isOtpExpired(notification)) {
      overrideTriggers.add('expired_otp');
    } else if (hasDeadline && _isReminderExpired(notification)) {
      overrideTriggers.add('expired_reminder');
    }

    // 6. Natural language explainability trace
    final explanation = ExplanationGenerator.generate(
      fusedResult: fusedResult,
      features: features,
      priority: priority,
    );

    stopwatch.stop();
    final latencyMs = stopwatch.elapsedMilliseconds;

    // Compute top feature attributions
    final attributions = ExplainabilityEngine.computeFeatureAttributions(
      notification: notification,
      features: features,
      featureVector: featureVector,
      overrideTriggers: overrideTriggers,
    );

    final attributionMap = <String, dynamic>{
      for (final attr in attributions) attr.label: attr.weight,
    };

    final featureVectorMap = <String, dynamic>{
      for (var i = 0; i < FeatureVector.featureNames.length && i < featureVector.length; i++)
        FeatureVector.featureNames[i]: featureVector[i],
    };

    // Create complete InferenceAuditLogEntry
    final auditLogEntry = InferenceAuditLogEntry(
      id: 'audit_${notification.id}_${DateTime.now().millisecondsSinceEpoch}',
      notificationId: notification.id,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      rawModelScore: ghostResult.predictedScore,
      ruleMatchScore: ghostResult.ruleScore,
      fusedScore: fusedResult.score,
      finalScore: ghostResult.reviewScore,
      overrideTriggers: overrideTriggers.join(','),
      topFeatureAttributions: attributionMap,
      inputFeatureVector: featureVectorMap,
      latencyMs: latencyMs,
    );

    // Cache in-memory and persist to Drift database table
    _inMemoryAuditLogs[notification.id] = auditLogEntry;
    if (auditLogDao != null) {
      try {
        await auditLogDao!.insertAuditLog(auditLogEntry);
      } catch (e) {
        // ignore error if db not available
      }
    }

    return notification.copyWith(
      priority: priority,
      priorityScore: ghostResult.reviewScore,
      classifiedCategory: fusedResult.category,
      explanation: explanation,
      latencyMs: latencyMs,
      ruleVersion: ruleEngine.version,
      modelVersion: GhostAI.instance.isModelLoaded ? '1.0.0-tflite' : 'fallback-heuristics',
      engineVersion: '2.0.0-hybrid',
      extractedFeatures: features.toMap(),
    );
  }

  bool _isOtpExpired(AppNotification notification) {
    final lower = notification.content.toLowerCase();
    final regex = RegExp(
      r'(?:valid|expires|active)\s+(?:for|in)?\s*(\d+)\s*(minute|minutes|min|mins|second|seconds|sec|secs)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(lower);
    int durationMs = 600000;
    if (match != null) {
      final amount = int.tryParse(match.group(1) ?? '');
      final unit = match.group(2)?.toLowerCase() ?? '';
      if (amount != null) {
        if (unit.startsWith('sec')) {
          durationMs = amount * 1000;
        } else {
          durationMs = amount * 60 * 1000;
        }
      }
    }
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - notification.timestamp;
    return elapsedMs > durationMs;
  }

  bool _isReminderExpired(AppNotification notification) {
    final lower = notification.content.toLowerCase();
    final relativeRegex = RegExp(
      r'\bin\s+(\d{1,4})\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b',
      caseSensitive: false,
    );
    final match = relativeRegex.firstMatch(lower);
    if (match != null) {
      final amount = int.tryParse(match.group(1) ?? '');
      final unit = match.group(2)?.toLowerCase() ?? '';
      if (amount != null) {
        int durationMs = 0;
        if (unit.startsWith('min')) {
          durationMs = amount * 60 * 1000;
        } else if (unit.startsWith('hour') || unit.startsWith('hr')) {
          durationMs = amount * 60 * 60 * 1000;
        } else {
          durationMs = amount * 24 * 60 * 60 * 1000;
        }
        final elapsedMs = DateTime.now().millisecondsSinceEpoch - notification.timestamp;
        return elapsedMs > durationMs;
      }
    }
    return false;
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
