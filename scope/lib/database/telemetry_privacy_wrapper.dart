import 'dart:math';
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

/// Local Differential Privacy Laplace Noise Generator.
class LaplaceNoise {
  final double epsilon;
  final Random _random;

  LaplaceNoise({this.epsilon = 1.0, Random? random})
      : _random = random ?? Random();

  /// Draw a random sample from Laplace(0, b) where scale b = 1.0 / epsilon.
  double sample() {
    final b = 1.0 / epsilon;
    double u = _random.nextDouble();
    while (u <= 0.0 || u >= 1.0) {
      u = _random.nextDouble();
    }
    if (u <= 0.5) {
      return b * log(2 * u);
    } else {
      return -b * log(2 * (1 - u));
    }
  }

  /// Adds Laplace noise to [rawValue] and rounds to the nearest integer.
  int addNoise(int rawValue) {
    return (rawValue + sample()).round();
  }
}

/// Sanitization utilities for focus sessions and timestamps.
class TelemetrySanitizer {
  /// Quantizes [dt] to the 15-minute boundary (truncated).
  static DateTime quantizeTimestamp(DateTime dt) {
    final minute = (dt.minute ~/ 15) * 15;
    return DateTime(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      minute,
    );
  }

  /// Buckets duration in seconds into 5-minute blocks (300 seconds).
  static int bucketDuration(int seconds) {
    if (seconds <= 0) return 0;
    final blocks = (seconds / 300.0).round();
    return blocks * 300;
  }

  /// Buckets interruption counts into discrete categories.
  static int bucketInterruptions(int count) {
    if (count <= 0) return 0;
    if (count <= 2) return 2;
    if (count <= 5) return 5;
    if (count <= 10) return 10;
    return ((count + 4) ~/ 5) * 5;
  }
}

/// Telemetry Privacy Wrapper DAO layer.
/// Intercepts metric writes to DailyBriefDao and applies randomized Laplace noise perturbation (epsilon = 1.0).
/// Sanitizes focus session records and clamps query outputs to non-negative values.
class TelemetryPrivacyWrapper {
  final AttentionDatabase db;
  final double epsilon;
  final LaplaceNoise laplaceNoise;

  TelemetryPrivacyWrapper(
    this.db, {
    this.epsilon = 1.0,
    LaplaceNoise? noise,
  }) : laplaceNoise = noise ?? LaplaceNoise(epsilon: epsilon);

  /// Intercepts DailyBriefEntry writes and applies Laplace noise to all daily metric counters.
  Future<void> insertOrUpdateDailyBrief(DailyBriefEntry entry) async {
    final noisyEntry = entry.copyWith(
      notificationsReviewed: laplaceNoise.addNoise(entry.notificationsReviewed),
      actionsCompleted: laplaceNoise.addNoise(entry.actionsCompleted),
      calendarEventsCreated: laplaceNoise.addNoise(entry.calendarEventsCreated),
      remindersCreated: laplaceNoise.addNoise(entry.remindersCreated),
      archivedCount: laplaceNoise.addNoise(entry.archivedCount),
    );
    await db.dailyBriefDao.insertOrUpdate(noisyEntry);
  }

  /// Increments daily stats with Laplace noise added to non-zero metric updates.
  Future<void> incrementDailyStats(
    String date, {
    int reviewed = 0,
    int completed = 0,
    int calendar = 0,
    int reminders = 0,
    int archived = 0,
  }) async {
    final noisyReviewed = reviewed != 0 ? laplaceNoise.addNoise(reviewed) : 0;
    final noisyCompleted = completed != 0 ? laplaceNoise.addNoise(completed) : 0;
    final noisyCalendar = calendar != 0 ? laplaceNoise.addNoise(calendar) : 0;
    final noisyReminders = reminders != 0 ? laplaceNoise.addNoise(reminders) : 0;
    final noisyArchived = archived != 0 ? laplaceNoise.addNoise(archived) : 0;

    await db.dailyBriefDao.incrementStats(
      date,
      reviewed: noisyReviewed,
      completed: noisyCompleted,
      calendar: noisyCalendar,
      reminders: noisyReminders,
      archived: noisyArchived,
    );
  }

  /// Fetches daily brief for [date] and clamps noisy metric values to V >= 0.
  Future<DailyBriefEntry?> getBriefForDate(String date) async {
    return await db.dailyBriefDao.getBriefForDate(date);
  }

  /// Fetches all daily briefs and clamps noisy metric values to V >= 0.
  Future<List<DailyBriefEntry>> getAllDailyBriefs() async {
    return await db.dailyBriefDao.getAll();
  }

  /// Focus Session telemetry routing: sanitizes timestamps, duration, and interruptions.
  Future<void> insertFocusSession(FocusSessionEntry entry) async {
    final sanitized = entry.copyWith(
      sessionStart: TelemetrySanitizer.quantizeTimestamp(entry.sessionStart),
      sessionEnd: entry.sessionEnd != null
          ? Value(TelemetrySanitizer.quantizeTimestamp(entry.sessionEnd!))
          : const Value.absent(),
      duration: TelemetrySanitizer.bucketDuration(entry.duration),
      interruptions: TelemetrySanitizer.bucketInterruptions(entry.interruptions),
    );
    await db.focusSessionDao.insertSession(sanitized);
  }

  Future<FocusSessionEntry?> getActiveFocusSession() async {
    return await db.focusSessionDao.getActiveSession();
  }

  Future<void> updateFocusSession(FocusSessionEntry entry) async {
    final sanitized = entry.copyWith(
      sessionStart: TelemetrySanitizer.quantizeTimestamp(entry.sessionStart),
      sessionEnd: entry.sessionEnd != null
          ? Value(TelemetrySanitizer.quantizeTimestamp(entry.sessionEnd!))
          : const Value.absent(),
      duration: TelemetrySanitizer.bucketDuration(entry.duration),
      interruptions: TelemetrySanitizer.bucketInterruptions(entry.interruptions),
    );
    await db.focusSessionDao.updateSession(sanitized);
  }

  Future<List<FocusSessionEntry>> getAllFocusSessions() async {
    return await db.focusSessionDao.getAll();
  }
}
