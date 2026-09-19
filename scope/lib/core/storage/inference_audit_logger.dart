import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/analysis/score_evolution_trace.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// Service managing structured, PII-sanitized inference audit logs.
class InferenceAuditLogger {
  final InferenceAuditLogDao? _auditDao;
  final List<InferenceAuditLogEntry> _inMemoryLogs = [];

  InferenceAuditLogger({InferenceAuditLogDao? auditDao}) : _auditDao = auditDao;

  /// Creates logger instance from AttentionDatabase.
  factory InferenceAuditLogger.fromDatabase(AttentionDatabase db) {
    return InferenceAuditLogger(auditDao: InferenceAuditLogDao(db));
  }

  /// Records an inference audit log entry.
  Future<void> logInference({
    required String notificationId,
    required String packageName,
    required int timestamp,
    required String classifiedCategory,
    required double predictedScore,
    required double fusedScore,
    required String finalPriority,
    required int latencyMs,
    required String overrideTrigger,
    required List<FeatureAttribution> attributions,
    required ScoreEvolutionTrace scoreTrace,
    bool isFallback = false,
  }) async {
    try {
      final sanitizedAttributions = attributions
          .map((a) => a.toMap())
          .toList();
      final attributionsJson = jsonEncode(sanitizedAttributions);
      final scoreEvolutionJson = scoreTrace.toJson();

      final entry = InferenceAuditLogEntry(
        id: 0, // Auto-incremented by SQLite
        notificationId: notificationId,
        packageName: packageName,
        timestamp: timestamp,
        classifiedCategory: classifiedCategory,
        predictedScore: predictedScore.isFinite ? predictedScore : 0.0,
        fusedScore: fusedScore.isFinite ? fusedScore : 0.0,
        finalPriority: finalPriority,
        latencyMs: latencyMs,
        overrideTrigger: overrideTrigger,
        featureAttributions: attributionsJson,
        scoreEvolution: scoreEvolutionJson,
        isFallback: isFallback,
        createdAt: DateTime.now(),
      );

      _inMemoryLogs.add(entry);

      if (_auditDao != null) {
        await _auditDao.insertAuditLog(entry);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InferenceAuditLogger failed to log audit entry: $e');
      }
    }
  }

  /// Retrieves audit log entry for a specific notification ID.
  Future<InferenceAuditLogEntry?> getAuditLogForNotification(String notificationId) async {
    if (_auditDao != null) {
      try {
        final entry = await _auditDao.getAuditLogForNotification(notificationId);
        if (entry != null) return entry;
      } catch (_) {}
    }
    return _inMemoryLogs
        .where((e) => e.notificationId == notificationId)
        .lastOrNull;
  }

  /// Retrieves all recorded audit logs.
  Future<List<InferenceAuditLogEntry>> getAllLogs() async {
    if (_auditDao != null) {
      try {
        final logs = await _auditDao.getAllLogs();
        if (logs.isNotEmpty) return logs;
      } catch (_) {}
    }
    return List.unmodifiable(_inMemoryLogs.reversed);
  }

  /// Prunes audit logs older than a given cutoff timestamp.
  Future<void> pruneOlderThan(int cutoffTimestamp) async {
    _inMemoryLogs.removeWhere((e) => e.timestamp < cutoffTimestamp);
    if (_auditDao != null) {
      try {
        await _auditDao.deleteOlderThan(cutoffTimestamp);
      } catch (_) {}
    }
  }

  /// Clears all audit logs.
  Future<void> clearAll() async {
    _inMemoryLogs.clear();
    if (_auditDao != null) {
      try {
        await _auditDao.clearAll();
      } catch (_) {}
    }
  }
}
