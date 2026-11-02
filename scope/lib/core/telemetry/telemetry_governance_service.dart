import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:scope/database/attention_database.dart';

/// Manages telemetry governance, differential privacy noise injection,
/// timestamp quantization, and entity-level privacy budget tracking across
/// AttentionOS / SCOPE metrics and sessions.
class TelemetryGovernanceService {
  TelemetryGovernanceService._();

  static const int epochIntervalMinutes = 15;
  static const int epochIntervalMs = 15 * 60 * 1000; // 900,000 ms
  static const double defaultEpsilon = 1.0;
  static const double maxPrivacyBudgetEpsilon = 2.0;
  static const double delta = 1e-5;

  static int _totalSanitizedSessions = 0;
  static int _totalSanitizedBriefs = 0;
  static double _spentPrivacyBudgetEpsilon = 0.0;

  /// Gets the accumulated spent privacy budget epsilon.
  static double get spentPrivacyBudgetEpsilon => _spentPrivacyBudgetEpsilon;

  /// Gets the remaining privacy budget epsilon.
  static double get remainingPrivacyBudgetEpsilon =>
      math.max(0.0, maxPrivacyBudgetEpsilon - _spentPrivacyBudgetEpsilon);

  /// Resets the privacy budget tracker (e.g. for a new day or test execution).
  static void resetPrivacyBudget() {
    _spentPrivacyBudgetEpsilon = 0.0;
    _logDiagnostic('Privacy budget reset.');
  }

  /// Attempts to consume a specified cost from the privacy budget.
  /// Returns `true` if budget was available and consumed; `false` otherwise.
  static bool tryConsumeBudget(double cost) {
    if (cost <= 0) return true;
    if (_spentPrivacyBudgetEpsilon + cost <= maxPrivacyBudgetEpsilon + 1e-9) {
      _spentPrivacyBudgetEpsilon += cost;
      return true;
    }
    _logDiagnostic(
      'Privacy budget limit exceeded. Spent: $_spentPrivacyBudgetEpsilon, Requested: $cost, Max: $maxPrivacyBudgetEpsilon',
    );
    return false;
  }

  /// Quantizes a [DateTime] timestamp to the preceding 15-minute epoch boundary.
  static DateTime quantizeTimestamp(DateTime timestamp) {
    try {
      final ms = timestamp.millisecondsSinceEpoch;
      final quantizedMs = quantizeTimestampMs(ms);
      return DateTime.fromMillisecondsSinceEpoch(quantizedMs, isUtc: timestamp.isUtc);
    } catch (e, st) {
      _logDiagnostic('Error quantizing timestamp: $e\n$st');
      return timestamp;
    }
  }

  /// Quantizes epoch milliseconds to the preceding 15-minute boundary (900,000 ms).
  static int quantizeTimestampMs(int timestampMs) {
    try {
      if (timestampMs <= 0) return 0;
      return (timestampMs ~/ epochIntervalMs) * epochIntervalMs;
    } catch (e) {
      return math.max(0, timestampMs);
    }
  }

  /// Quantizes focus session duration in seconds to fixed buckets.
  /// Default bucket size is 300 seconds (5 minutes).
  static int quantizeDuration(int durationSeconds, {int bucketSizeSeconds = 300}) {
    try {
      if (durationSeconds <= 0) return 0;
      if (bucketSizeSeconds <= 0) return durationSeconds;
      return (durationSeconds ~/ bucketSizeSeconds) * bucketSizeSeconds;
    } catch (e) {
      return math.max(0, durationSeconds);
    }
  }

  /// Quantizes focus session interruption counts.
  /// Non-negative integer clamped to [maxCap].
  static int quantizeInterruptions(int interruptions, {int maxCap = 10}) {
    try {
      if (interruptions <= 0) return 0;
      return math.min(interruptions, maxCap);
    } catch (e) {
      return 0;
    }
  }

  /// Injects zero-mean Laplace noise L(0, b) into a metric value.
  /// Scale b = sensitivity / epsilon.
  /// The result is clamped to >= 0.
  static num addLaplaceNoise(
    num value, {
    double sensitivity = 1.0,
    double epsilon = defaultEpsilon,
    math.Random? random,
  }) {
    try {
      final safeValue = value.isNaN || value.isInfinite ? 0 : value;
      final safeEpsilon = epsilon <= 0 ? 1e-6 : epsilon;
      final safeSensitivity = sensitivity <= 0 ? 1.0 : sensitivity;

      final rand = random ?? math.Random();
      double u = rand.nextDouble() - 0.5;
      while (u == 0.0 || u == -0.5 || u == 0.5) {
        u = rand.nextDouble() - 0.5;
      }

      final scale = safeSensitivity / safeEpsilon;
      final noise = -scale * (u.sign) * math.log(1.0 - 2.0 * u.abs());
      final noisyValue = (safeValue + noise).round();

      return math.max(0, noisyValue);
    } catch (e, st) {
      _logDiagnostic('Error adding Laplace noise: $e\n$st');
      return math.max(0, value.round());
    }
  }

  /// Sanitizes a [FocusSessionEntry] before database persistence.
  /// Applies 15-minute timestamp quantization and duration/interruption quantization.
  static FocusSessionEntry sanitizeFocusSession(
    FocusSessionEntry session, {
    int durationBucketSeconds = 300,
    int maxInterruptionsCap = 10,
  }) {
    try {
      final sanitizedStart = quantizeTimestamp(session.sessionStart);
      final sanitizedEnd = session.sessionEnd != null
          ? quantizeTimestamp(session.sessionEnd!)
          : null;
      final sanitizedDuration = quantizeDuration(
        session.duration,
        bucketSizeSeconds: durationBucketSeconds,
      );
      final sanitizedInterruptions = quantizeInterruptions(
        session.interruptions,
        maxCap: maxInterruptionsCap,
      );

      _totalSanitizedSessions++;

      return session.copyWith(
        sessionStart: sanitizedStart,
        sessionEnd: Value(sanitizedEnd),
        duration: sanitizedDuration,
        interruptions: sanitizedInterruptions,
      );
    } catch (e, st) {
      _logDiagnostic('Error sanitizing focus session: $e\n$st');
      return session;
    }
  }

  /// Sanitizes a [DailyBriefEntry] before database persistence.
  /// Applies differential privacy Laplace noise to metric counts.
  static DailyBriefEntry sanitizeDailyBrief(
    DailyBriefEntry brief, {
    double epsilon = defaultEpsilon,
    double sensitivity = 1.0,
    math.Random? random,
  }) {
    try {
      final budgetAvailable = tryConsumeBudget(epsilon);
      final effectiveEpsilon = budgetAvailable ? epsilon : maxPrivacyBudgetEpsilon;

      final noisyReviewed = addLaplaceNoise(
        brief.notificationsReviewed,
        sensitivity: sensitivity,
        epsilon: effectiveEpsilon,
        random: random,
      ).toInt();

      final noisyCompleted = addLaplaceNoise(
        brief.actionsCompleted,
        sensitivity: sensitivity,
        epsilon: effectiveEpsilon,
        random: random,
      ).toInt();

      final noisyCalendar = addLaplaceNoise(
        brief.calendarEventsCreated,
        sensitivity: sensitivity,
        epsilon: effectiveEpsilon,
        random: random,
      ).toInt();

      final noisyReminders = addLaplaceNoise(
        brief.remindersCreated,
        sensitivity: sensitivity,
        epsilon: effectiveEpsilon,
        random: random,
      ).toInt();

      final noisyArchived = addLaplaceNoise(
        brief.archivedCount,
        sensitivity: sensitivity,
        epsilon: effectiveEpsilon,
        random: random,
      ).toInt();

      _totalSanitizedBriefs++;

      return brief.copyWith(
        notificationsReviewed: noisyReviewed,
        actionsCompleted: noisyCompleted,
        calendarEventsCreated: noisyCalendar,
        remindersCreated: noisyReminders,
        archivedCount: noisyArchived,
      );
    } catch (e, st) {
      _logDiagnostic('Error sanitizing daily brief: $e\n$st');
      return brief;
    }
  }

  /// Returns diagnostic telemetry and audit metrics for monitoring system state.
  static Map<String, dynamic> getAuditMetrics() {
    return {
      'total_sanitized_sessions': _totalSanitizedSessions,
      'total_sanitized_briefs': _totalSanitizedBriefs,
      'spent_privacy_budget_epsilon': _spentPrivacyBudgetEpsilon,
      'max_privacy_budget_epsilon': maxPrivacyBudgetEpsilon,
      'remaining_privacy_budget_epsilon': remainingPrivacyBudgetEpsilon,
      'epoch_interval_minutes': epochIntervalMinutes,
      'delta': delta,
    };
  }

  static void _logDiagnostic(String message) {
    if (kDebugMode) {
      developer.log(message, name: 'TelemetryGovernanceService');
    }
  }
}
