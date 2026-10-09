import 'dart:math';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// Service that tracks cumulative privacy loss in a local SQLite ledger while
/// applying Laplace noise injection and sensitivity clipping before persisting telemetry metrics.
///
/// Enforces budget exhaustion limits by clamping or suppressing behavioral updates
/// once the daily privacy threshold is reached.
class PrivacyBudgetManager {
  final AttentionDatabase? _db;
  final double defaultDailyEpsilon;
  final double delta;

  // Global sensitivity constants
  static const double sDuration = 3600.0; // Seconds (max 1 hour per focus session)
  static const double sInterruption = 10.0; // Max interruptions per session
  static const double sCount = 10.0; // Max count per daily activity update

  // Default cost per telemetry update
  static const double defaultOpEpsilon = 0.1;

  PrivacyBudgetManager({
    AttentionDatabase? db,
    this.defaultDailyEpsilon = 1.0,
    this.delta = 1e-5,
  }) : _db = db;

  PrivacyBudgetDao? get _dao => _db?.privacyBudgetDao;

  String _formatDate(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Gets the remaining privacy budget (epsilon) for today's daily window.
  /// Automatically initializes or replenishes budget if a new date boundary is crossed.
  Future<double> getRemainingBudget({DateTime? now}) async {
    final dt = now ?? DateTime.now();
    final dateStr = _formatDate(dt);

    if (_dao == null) {
      return defaultDailyEpsilon;
    }

    final entry = await _dao!.getEntryForDate(dateStr);
    if (entry == null) {
      // Midnight reset / new daily window initialization
      final newEntry = PrivacyBudgetEntry(
        date: dateStr,
        usedEpsilon: 0.0,
        maxEpsilon: defaultDailyEpsilon,
        lastUpdated: dt,
      );
      await _dao!.upsertEntry(newEntry);
      return defaultDailyEpsilon;
    }

    final remaining = entry.maxEpsilon - entry.usedEpsilon;
    return max(0.0, remaining);
  }

  /// Gets the used privacy budget (epsilon) for today's daily window.
  Future<double> getUsedBudget({DateTime? now}) async {
    final dt = now ?? DateTime.now();
    final dateStr = _formatDate(dt);

    if (_dao == null) {
      return 0.0;
    }

    final entry = await _dao!.getEntryForDate(dateStr);
    return entry?.usedEpsilon ?? 0.0;
  }

  /// Checks whether budget is available for an operation with [epsilonCost].
  Future<bool> canConsumeBudget(double epsilonCost, {DateTime? now}) async {
    final remaining = await getRemainingBudget(now: now);
    return remaining >= epsilonCost && remaining > 0;
  }

  /// Consumes [epsilonCost] from today's privacy budget ledger.
  /// Returns `true` if budget was available and successfully consumed.
  /// Returns `false` if the remaining daily budget is exhausted (<= 0).
  Future<bool> consumeBudget(double epsilonCost, {DateTime? now}) async {
    final dt = now ?? DateTime.now();
    final dateStr = _formatDate(dt);

    final remaining = await getRemainingBudget(now: dt);
    if (remaining <= 0 || remaining < epsilonCost) {
      return false; // Budget exhausted!
    }

    if (_dao != null) {
      final entry = await _dao!.getEntryForDate(dateStr);
      final currentUsed = entry?.usedEpsilon ?? 0.0;
      final maxEps = entry?.maxEpsilon ?? defaultDailyEpsilon;

      final updatedEntry = PrivacyBudgetEntry(
        date: dateStr,
        usedEpsilon: min(maxEps, currentUsed + epsilonCost),
        maxEpsilon: maxEps,
        lastUpdated: dt,
      );
      await _dao!.upsertEntry(updatedEntry);
    }

    return true;
  }

  /// Resets today's privacy budget ledger (used for testing or explicit admin reset).
  Future<void> resetBudget({DateTime? now, double? newMaxEpsilon}) async {
    final dt = now ?? DateTime.now();
    final dateStr = _formatDate(dt);

    if (_dao != null) {
      final entry = await _dao!.getEntryForDate(dateStr);
      final maxEps = newMaxEpsilon ?? entry?.maxEpsilon ?? defaultDailyEpsilon;

      await _dao!.upsertEntry(PrivacyBudgetEntry(
        date: dateStr,
        usedEpsilon: 0.0,
        maxEpsilon: maxEps,
        lastUpdated: dt,
      ));
    }
  }

  /// Clips [value] to [minVal, maxVal].
  double clipValue(num value, {required double minVal, required double maxVal}) {
    return value.toDouble().clamp(minVal, maxVal);
  }

  /// Generates a Laplace noise sample Lap(0, scale) where scale = sensitivity / epsilon.
  /// Uses inverse transform sampling: N = -scale * sgn(u - 0.5) * ln(1 - 2*|u - 0.5|).
  double sampleLaplaceNoise({
    required double sensitivity,
    required double epsilon,
    Random? random,
  }) {
    if (epsilon <= 0) return 0.0;

    final scale = sensitivity / epsilon;
    final rng = random ?? Random();

    // Draw uniform random u in (0, 1)
    double u = rng.nextDouble();
    // Clamp to avoid log(0)
    u = u.clamp(1e-12, 1.0 - 1e-12);

    if (u < 0.5) {
      return scale * log(2.0 * u);
    } else {
      return -scale * log(2.0 * (1.0 - u));
    }
  }

  /// Applies sensitivity clipping and Laplace noise injection to an integer metric.
  ///
  /// First clips [rawValue] to [minVal, sensitivity], draws Laplace noise proportional to
  /// [sensitivity] / [epsilon], rounds to integer, and clamps to physical bounds [minVal, maxVal].
  int applyNoisyClippingInt(
    int rawValue, {
    required double sensitivity,
    required double epsilon,
    int minVal = 0,
    int maxVal = 100000,
    Random? random,
  }) {
    final clipped = clipValue(rawValue, minVal: minVal.toDouble(), maxVal: minVal + sensitivity);
    final noise = sampleLaplaceNoise(sensitivity: sensitivity, epsilon: epsilon, random: random);
    final noisyVal = (clipped + noise).round();
    return noisyVal.clamp(minVal, maxVal);
  }

  /// Clips focus session duration to [0, S_duration] and applies Laplace noise.
  int applyNoisyDuration(
    int rawDurationSeconds, {
    double epsilon = defaultOpEpsilon,
    Random? random,
  }) {
    return applyNoisyClippingInt(
      rawDurationSeconds,
      sensitivity: sDuration,
      epsilon: epsilon,
      minVal: 0,
      maxVal: sDuration.toInt(),
      random: random,
    );
  }

  /// Clips focus session interruptions to [0, S_interruption] and applies Laplace noise.
  int applyNoisyInterruptions(
    int rawInterruptions, {
    double epsilon = defaultOpEpsilon,
    Random? random,
  }) {
    return applyNoisyClippingInt(
      rawInterruptions,
      sensitivity: sInterruption,
      epsilon: epsilon,
      minVal: 0,
      maxVal: sInterruption.toInt(),
      random: random,
    );
  }

  /// Clips daily activity count metrics to [0, S_count] and applies Laplace noise.
  int applyNoisyCount(
    int rawCount, {
    double epsilon = defaultOpEpsilon,
    Random? random,
  }) {
    return applyNoisyClippingInt(
      rawCount,
      sensitivity: sCount,
      epsilon: epsilon,
      minVal: 0,
      maxVal: 10000,
      random: random,
    );
  }
}
