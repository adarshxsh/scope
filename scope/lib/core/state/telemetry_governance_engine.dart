import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// Central governance engine enforcing local differential privacy guardrails
/// (Laplace noise injection) and temporal bucketing (15-min start/end timestamps,
/// 5-min duration quantization) on all telemetry and activity metrics.
class TelemetryGovernanceEngine {
  final double epsilon;
  final math.Random? _random;

  TelemetryGovernanceEngine({
    this.epsilon = 0.5,
    math.Random? random,
  }) : _random = random;

  /// Rounds a [DateTime] timestamp to the nearest 15-minute time boundary.
  DateTime roundTo15Minutes(DateTime dt) {
    final totalSeconds = dt.minute * 60 + dt.second + dt.millisecond / 1000.0;
    final roundedQuarterIndex = (totalSeconds / 900.0).round();
    final roundedMinute = roundedQuarterIndex * 15;
    return DateTime(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      0,
      0,
    ).add(Duration(minutes: roundedMinute));
  }

  /// Quantizes session duration in seconds to discrete 5-minute duration bins
  /// (multiples of 300 seconds, e.g., 0, 300, 600, 900 seconds).
  int quantizeDurationSeconds(int durationSeconds) {
    if (durationSeconds <= 0) return 0;
    final bins = (durationSeconds / 300.0).round();
    return bins * 300;
  }

  /// Generates a sample from zero-mean Laplace distribution Lap(0, 1/epsilon)
  /// using inverse transform sampling.
  double generateLaplaceNoise({double? overrideEpsilon, math.Random? random}) {
    final eps = overrideEpsilon ?? epsilon;
    if (eps <= 0) return 0.0;
    final rng = random ?? _random ?? math.Random();

    double u = rng.nextDouble() - 0.5;
    while (u == 0 || u == -0.5 || u == 0.5) {
      u = rng.nextDouble() - 0.5;
    }

    final b = 1.0 / eps;
    final sign = u < 0 ? -1.0 : 1.0;
    return -b * sign * math.log(1.0 - 2.0 * u.abs());
  }

  /// Applies Laplace noise to a raw integer value, rounds to nearest integer,
  /// and clamps the result to a non-negative integer (>= 0).
  int applyLaplaceNoise(
    int rawValue, {
    double? overrideEpsilon,
    math.Random? random,
  }) {
    final noise = generateLaplaceNoise(
      overrideEpsilon: overrideEpsilon,
      random: random,
    );
    final noisy = (rawValue + noise).round();
    return math.max(0, noisy);
  }

  /// Governs a [FocusSessionEntry] before database persistence, ensuring
  /// start and end timestamps are aligned to 15-minute time windows and
  /// duration is quantized to 5-minute bins.
  FocusSessionEntry governFocusSession(FocusSessionEntry entry) {
    final start = roundTo15Minutes(entry.sessionStart);
    final end = entry.sessionEnd != null ? roundTo15Minutes(entry.sessionEnd!) : null;
    final duration = quantizeDurationSeconds(entry.duration);

    return entry.copyWith(
      sessionStart: start,
      sessionEnd: Value(end),
      duration: duration,
    );
  }

  /// Governs a [DailyBriefEntry] before database persistence, passing all
  /// 5 activity counters through Laplace noise injection and non-negative clamping.
  DailyBriefEntry governDailyBrief(
    DailyBriefEntry entry, {
    double? overrideEpsilon,
    math.Random? random,
  }) {
    return entry.copyWith(
      notificationsReviewed: applyLaplaceNoise(
        entry.notificationsReviewed,
        overrideEpsilon: overrideEpsilon,
        random: random,
      ),
      actionsCompleted: applyLaplaceNoise(
        entry.actionsCompleted,
        overrideEpsilon: overrideEpsilon,
        random: random,
      ),
      calendarEventsCreated: applyLaplaceNoise(
        entry.calendarEventsCreated,
        overrideEpsilon: overrideEpsilon,
        random: random,
      ),
      remindersCreated: applyLaplaceNoise(
        entry.remindersCreated,
        overrideEpsilon: overrideEpsilon,
        random: random,
      ),
      archivedCount: applyLaplaceNoise(
        entry.archivedCount,
        overrideEpsilon: overrideEpsilon,
        random: random,
      ),
    );
  }

  /// Records or updates daily brief activity counts via [DailyBriefDao], applying
  /// Laplace noise to increments before writing to database.
  Future<void> recordDailyBriefMetric(
    DailyBriefDao dao,
    String date, {
    int reviewed = 0,
    int completed = 0,
    int calendar = 0,
    int reminders = 0,
    int archived = 0,
  }) async {
    await dao.incrementStats(
      date,
      reviewed: reviewed,
      completed: completed,
      calendar: calendar,
      reminders: reminders,
      archived: archived,
      governanceEngine: this,
    );
  }
}
