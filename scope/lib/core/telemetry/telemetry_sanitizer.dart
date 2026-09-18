import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

/// Standardized categories for focus session durations.
enum FocusDurationCategory {
  under5Min,
  min5To15,
  min15To30,
  min30To60,
  over60Min;

  /// Human-readable category label.
  String get label {
    switch (this) {
      case FocusDurationCategory.under5Min:
        return '< 5 mins';
      case FocusDurationCategory.min5To15:
        return '5-15 mins';
      case FocusDurationCategory.min15To30:
        return '15-30 mins';
      case FocusDurationCategory.min30To60:
        return '30-60 mins';
      case FocusDurationCategory.over60Min:
        return '> 60 mins';
    }
  }

  /// Standardized discretized duration in seconds assigned to this bucket.
  int get bucketDurationSeconds {
    switch (this) {
      case FocusDurationCategory.under5Min:
        return 300; // 5 mins
      case FocusDurationCategory.min5To15:
        return 600; // 10 mins (midpoint)
      case FocusDurationCategory.min15To30:
        return 1200; // 20 mins
      case FocusDurationCategory.min30To60:
        return 2400; // 40 mins
      case FocusDurationCategory.over60Min:
        return 3600; // 60 mins
    }
  }
}

/// Helper for categorizing raw focus session durations into fixed time buckets.
class FocusDurationCategorizer {
  /// Categorizes a raw duration in seconds into a [FocusDurationCategory].
  static FocusDurationCategory categorizeSeconds(int seconds) {
    if (seconds < 300) {
      return FocusDurationCategory.under5Min;
    } else if (seconds < 900) {
      return FocusDurationCategory.min5To15;
    } else if (seconds < 1800) {
      return FocusDurationCategory.min15To30;
    } else if (seconds < 3600) {
      return FocusDurationCategory.min30To60;
    } else {
      return FocusDurationCategory.over60Min;
    }
  }

  /// Categorizes a [Duration] object into a [FocusDurationCategory].
  static FocusDurationCategory categorize(Duration duration) {
    return categorizeSeconds(duration.inSeconds);
  }

  /// Returns the discretized duration in seconds for a raw duration.
  static int discretizeSeconds(int seconds) {
    return categorizeSeconds(seconds).bucketDurationSeconds;
  }

  /// Returns the category label for a raw duration in seconds.
  static String categorizeLabel(int seconds) {
    return categorizeSeconds(seconds).label;
  }
}

/// Container for raw or sanitized daily engagement counter metrics.
class DailyEngagementMetrics {
  final int notificationsReviewed;
  final int actionsCompleted;
  final int calendarEventsCreated;
  final int remindersCreated;
  final int archivedCount;

  const DailyEngagementMetrics({
    this.notificationsReviewed = 0,
    this.actionsCompleted = 0,
    this.calendarEventsCreated = 0,
    this.remindersCreated = 0,
    this.archivedCount = 0,
  });

  DailyEngagementMetrics copyWith({
    int? notificationsReviewed,
    int? actionsCompleted,
    int? calendarEventsCreated,
    int? remindersCreated,
    int? archivedCount,
  }) {
    return DailyEngagementMetrics(
      notificationsReviewed: notificationsReviewed ?? this.notificationsReviewed,
      actionsCompleted: actionsCompleted ?? this.actionsCompleted,
      calendarEventsCreated: calendarEventsCreated ?? this.calendarEventsCreated,
      remindersCreated: remindersCreated ?? this.remindersCreated,
      archivedCount: archivedCount ?? this.archivedCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyEngagementMetrics &&
          runtimeType == other.runtimeType &&
          notificationsReviewed == other.notificationsReviewed &&
          actionsCompleted == other.actionsCompleted &&
          calendarEventsCreated == other.calendarEventsCreated &&
          remindersCreated == other.remindersCreated &&
          archivedCount == other.archivedCount;

  @override
  int get hashCode =>
      notificationsReviewed.hashCode ^
      actionsCompleted.hashCode ^
      calendarEventsCreated.hashCode ^
      remindersCreated.hashCode ^
      archivedCount.hashCode;

  @override
  String toString() =>
      'DailyEngagementMetrics(reviewed: $notificationsReviewed, actions: $actionsCompleted, calendar: $calendarEventsCreated, reminders: $remindersCreated, archived: $archivedCount)';
}

/// On-device Local Differential Privacy (LDP) middleware that sanitizes daily engagement metrics
/// with bounded Laplace noise and discretizes focus session durations into fixed time categories.
class TelemetrySanitizationMiddleware {
  final double epsilon;
  final double sensitivity;
  final math.Random? _random;

  TelemetrySanitizationMiddleware({
    this.epsilon = 1.0,
    this.sensitivity = 1.0,
    math.Random? random,
  })  : assert(epsilon > 0, 'Epsilon privacy parameter must be strictly positive.'),
        assert(sensitivity > 0, 'Sensitivity parameter must be strictly positive.'),
        _random = random;

  /// Laplace scale parameter b = sensitivity / epsilon.
  double get scale => sensitivity / epsilon;

  /// Samples Laplace noise from Lap(0, scale) using inverse transform sampling.
  double sampleLaplaceNoise({double? customScale}) {
    final b = customScale ?? scale;
    final r = _random ?? math.Random();
    // Sample u uniformly from (-0.5, 0.5)
    final u = r.nextDouble() - 0.5;
    // Clamp u to avoid log(0) at bounds
    final clampedU = u.clamp(-0.499999999, 0.499999999);
    final sgn = clampedU < 0 ? -1.0 : 1.0;
    return -b * sgn * math.log(1.0 - 2.0 * clampedU.abs());
  }

  /// Sanitizes a single counter by injecting Laplace noise, rounding to the nearest integer,
  /// and clamping lower/upper bounds to prevent negative values or unreasonable spikes.
  int sanitizeCounter(
    int rawValue, {
    int lowerBound = 0,
    int? upperBound,
    int? maxSpikeDelta,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      final noise = sampleLaplaceNoise();
      int noisyValue = (rawValue + noise).round();

      // Enforce non-negative lower bound
      if (noisyValue < lowerBound) {
        noisyValue = lowerBound;
      }

      // Enforce optional upper bound or max spike limit
      if (maxSpikeDelta != null && noisyValue > rawValue + maxSpikeDelta) {
        noisyValue = rawValue + maxSpikeDelta;
      }
      if (upperBound != null && noisyValue > upperBound) {
        noisyValue = upperBound;
      }

      return noisyValue;
    } finally {
      stopwatch.stop();
      // Verify performance overhead is strictly under 50 ms
      assert(stopwatch.elapsedMilliseconds < 50, 'Metric sanitization exceeded 50ms SLA.');
    }
  }

  /// Intercepts and sanitizes all daily engagement counter metrics before persistence.
  DailyEngagementMetrics sanitizeMetrics(DailyEngagementMetrics rawMetrics) {
    final stopwatch = Stopwatch()..start();
    try {
      return DailyEngagementMetrics(
        notificationsReviewed: sanitizeCounter(rawMetrics.notificationsReviewed),
        actionsCompleted: sanitizeCounter(rawMetrics.actionsCompleted),
        calendarEventsCreated: sanitizeCounter(rawMetrics.calendarEventsCreated),
        remindersCreated: sanitizeCounter(rawMetrics.remindersCreated),
        archivedCount: sanitizeCounter(rawMetrics.archivedCount),
      );
    } finally {
      stopwatch.stop();
      assert(stopwatch.elapsedMilliseconds < 50, 'Metrics sanitization transaction exceeded 50ms SLA.');
    }
  }

  /// Sanitize and discretize a [FocusSessionEntry] before writing to storage.
  /// Converts exact raw durations into standardized categories and removes exact millisecond timestamps.
  FocusSessionEntry sanitizeFocusSession(
    FocusSessionEntry rawEntry, {
    int? rawDurationSeconds,
  }) {
    final rawSec = rawDurationSeconds ?? rawEntry.duration;
    final category = FocusDurationCategorizer.categorizeSeconds(rawSec);
    final discretizedSec = category.bucketDurationSeconds;

    // Truncate timestamps to minute resolution to destroy exact millisecond/second routine traces
    final sanitizedStart = DateTime(
      rawEntry.sessionStart.year,
      rawEntry.sessionStart.month,
      rawEntry.sessionStart.day,
      rawEntry.sessionStart.hour,
      rawEntry.sessionStart.minute,
    );

    final sanitizedEnd = rawEntry.sessionEnd != null
        ? DateTime(
            rawEntry.sessionEnd!.year,
            rawEntry.sessionEnd!.month,
            rawEntry.sessionEnd!.day,
            rawEntry.sessionEnd!.hour,
            rawEntry.sessionEnd!.minute,
          )
        : null;

    return rawEntry.copyWith(
      sessionStart: sanitizedStart,
      sessionEnd: Value(sanitizedEnd),
      duration: discretizedSec,
      durationCategory: Value(category.label),
    );
  }
}
