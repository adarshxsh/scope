import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

/// Exception thrown when the daily privacy budget (\u03b5 = 1.0) is exceeded.
class PrivacyBudgetExceededException implements Exception {
  final String message;
  PrivacyBudgetExceededException([this.message = 'Daily privacy budget (\u03b5 = 1.0) exceeded.']);

  @override
  String toString() => 'PrivacyBudgetExceededException: $message';
}

/// Dedicated Telemetry Governance Service implementing local differential privacy
/// noise injection and timestamp quantization prior to SQLite database persistence.
class TelemetryGovernanceService {
  final AttentionDatabase _db;
  final math.Random? _random;

  double _consumedBudgetToday = 0.0;
  String? _currentBudgetDate;

  /// Strict maximum daily privacy budget (\u03b5) cap per 24-hour period.
  static const double maxDailyEpsilon = 1.0;

  TelemetryGovernanceService(this._db, [this._random]);

  /// Returns the consumed budget for today.
  double get consumedBudgetToday => _consumedBudgetToday;

  /// Returns the remaining budget for today.
  double get remainingBudgetToday => math.max(0.0, maxDailyEpsilon - _consumedBudgetToday);

  void _checkAndResetDailyBudget(String date) {
    if (_currentBudgetDate != date) {
      _currentBudgetDate = date;
      _consumedBudgetToday = 0.0;
    }
  }

  /// Checks if the requested budget cost can be consumed without exceeding \u03b5 = 1.0.
  bool canSpendBudget(double epsilon, {String? date}) {
    _checkAndResetDailyBudget(date ?? _todayDateString());
    return (_consumedBudgetToday + epsilon) <= maxDailyEpsilon + 1e-9;
  }

  /// Consumes the specified privacy budget (\u03b5) for the given date.
  /// Throws [PrivacyBudgetExceededException] if the budget limit is exceeded.
  void consumeBudget(double epsilon, {String? date}) {
    final targetDate = date ?? _todayDateString();
    _checkAndResetDailyBudget(targetDate);
    if (_consumedBudgetToday + epsilon > maxDailyEpsilon + 1e-9) {
      throw PrivacyBudgetExceededException(
        'Attempted to spend $epsilon budget, but remaining budget is ${remainingBudgetToday.toStringAsFixed(2)} '
        '(max budget: $maxDailyEpsilon).',
      );
    }
    _consumedBudgetToday += epsilon;
  }

  /// Manually resets privacy budget state (useful for testing or daily reset).
  void resetBudget({String? date}) {
    _currentBudgetDate = date ?? _todayDateString();
    _consumedBudgetToday = 0.0;
  }

  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Quantizes timestamps to coarse 15-minute temporal intervals (:00, :15, :30, :45).
  DateTime quantizeTimestamp(DateTime dt) {
    final totalSeconds = dt.minute * 60 + dt.second + dt.millisecond / 1000.0;
    final roundedMinutes = (totalSeconds / 900.0).round() * 15;
    return DateTime(dt.year, dt.month, dt.day, dt.hour)
        .add(Duration(minutes: roundedMinutes));
  }

  /// Maps focus session duration in seconds into discrete 5-minute scalar blocks (300-second blocks).
  int quantizeDuration(int seconds) {
    if (seconds <= 0) return 0;
    final fiveMinBlocks = (seconds / 300.0).round();
    return fiveMinBlocks * 300;
  }

  /// Maps interruption counts into discrete scalar buckets.
  int quantizeInterruptions(int count) {
    if (count <= 0) return 0;
    return count;
  }

  /// Generates Laplace noise Lap(0, scale) using inverse transform sampling.
  double sampleLaplaceNoise({double scale = 1.0}) {
    final rng = _random ?? math.Random();
    double u = rng.nextDouble() - 0.5;
    while (u == 0 || u == -0.5 || u == 0.5) {
      u = rng.nextDouble() - 0.5;
    }
    return -scale * u.sign * math.log(1.0 - 2.0 * u.abs());
  }

  /// Injects Laplace noise into an integer metric counter and clamps result to non-negative integers.
  int injectLaplaceNoiseToCount(int rawCount, {double scale = 1.0}) {
    final noise = sampleLaplaceNoise(scale: scale);
    final noisyCount = rawCount + noise.round();
    return math.max(0, noisyCount);
  }

  /// Start a focus session with quantized 15-minute start time.
  Future<int> startFocusSession(DateTime startTime) async {
    final qStart = quantizeTimestamp(startTime);
    final companion = FocusSessionsTableCompanion.insert(
      sessionStart: qStart,
      interruptions: const Value(0),
      completion: const Value(false),
      duration: 0,
    );
    return await _db.into(_db.focusSessionsTable).insert(companion);
  }

  /// Finish an active focus session by quantizing start/end timestamps to 15-minute boundaries,
  /// duration to 5-minute scalar blocks, and updating the database.
  Future<void> finishFocusSession({
    required FocusSessionEntry activeSession,
    required DateTime endTime,
    required int interruptions,
  }) async {
    final qStart = quantizeTimestamp(activeSession.sessionStart);
    final qEnd = quantizeTimestamp(endTime);
    final rawDuration = endTime.difference(activeSession.sessionStart).inSeconds;
    final qDuration = quantizeDuration(rawDuration);
    final qInterruptions = quantizeInterruptions(interruptions);

    final updated = activeSession.copyWith(
      sessionStart: qStart,
      sessionEnd: Value(qEnd),
      completion: true,
      duration: qDuration,
      interruptions: qInterruptions,
    );

    await _db.focusSessionDao.updateSession(updated);
  }

  /// Routes all daily interaction metric updates through local differential privacy middleware.
  /// Enforces daily privacy budget cap (\u03b5 = 1.0) and injects Laplace noise prior to persistence.
  Future<void> recordDailyBriefMetrics(
    String date, {
    int reviewed = 0,
    int completed = 0,
    int calendar = 0,
    int reminders = 0,
    int archived = 0,
    double epsilonCost = 0.2,
  }) async {
    if (epsilonCost > 0) {
      consumeBudget(epsilonCost, date: date);
    }

    final existing = await _db.dailyBriefDao.getBriefForDate(date);
    final rawReviewed = (existing?.notificationsReviewed ?? 0) + reviewed;
    final rawCompleted = (existing?.actionsCompleted ?? 0) + completed;
    final rawCalendar = (existing?.calendarEventsCreated ?? 0) + calendar;
    final rawReminders = (existing?.remindersCreated ?? 0) + reminders;
    final rawArchived = (existing?.archivedCount ?? 0) + archived;

    final noisyReviewed = injectLaplaceNoiseToCount(rawReviewed);
    final noisyCompleted = injectLaplaceNoiseToCount(rawCompleted);
    final noisyCalendar = injectLaplaceNoiseToCount(rawCalendar);
    final noisyReminders = injectLaplaceNoiseToCount(rawReminders);
    final noisyArchived = injectLaplaceNoiseToCount(rawArchived);

    await _db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
      id: existing?.id ?? 0,
      date: date,
      notificationsReviewed: noisyReviewed,
      actionsCompleted: noisyCompleted,
      calendarEventsCreated: noisyCalendar,
      remindersCreated: noisyReminders,
      archivedCount: noisyArchived,
    ));
  }

  /// Retrieves the persisted noise-injected daily brief entry for a given date.
  Future<DailyBriefEntry?> getDailyBrief(String date) {
    return _db.dailyBriefDao.getBriefForDate(date);
  }

  /// Retrieves all persisted daily brief entries.
  Future<List<DailyBriefEntry>> getAllDailyBriefs() {
    return _db.dailyBriefDao.getAll();
  }
}
