import 'dart:math';
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

/// TelemetryGovernanceService enforces on-device differential privacy governance
/// and timestamp quantization prior to persisting behavioral telemetry metrics.
class TelemetryGovernanceService {
  final double defaultEpsilon;
  final double defaultSensitivity;
  final bool isNoiseEnabled;
  final bool isQuantizationEnabled;
  final Random _random;

  // Track consumed and maximum privacy budget (epsilon) per telemetry entity
  final Map<String, double> _consumedBudget = {};
  final Map<String, double> _maxBudget = {};

  TelemetryGovernanceService({
    this.defaultEpsilon = 1.0,
    this.defaultSensitivity = 1.0,
    this.isNoiseEnabled = true,
    this.isQuantizationEnabled = true,
    Random? random,
  }) : _random = random ?? Random();

  /// Sets the maximum privacy budget (epsilon) allowed for a telemetry entity.
  void setMaxBudget(String entity, double maxEpsilon) {
    _maxBudget[entity] = maxEpsilon;
  }

  /// Returns the maximum privacy budget for a telemetry entity (defaults to [defaultEpsilon]).
  double getMaxBudget(String entity) {
    return _maxBudget[entity] ?? defaultEpsilon;
  }

  /// Returns the consumed privacy budget for a telemetry entity.
  double getConsumedBudget(String entity) {
    return _consumedBudget[entity] ?? 0.0;
  }

  /// Returns the remaining privacy budget for a telemetry entity.
  double getRemainingBudget(String entity) {
    final remaining = getMaxBudget(entity) - getConsumedBudget(entity);
    return remaining < 0.0 ? 0.0 : remaining;
  }

  /// Checks whether a telemetry entity has sufficient remaining privacy budget.
  bool hasBudget(String entity, double requiredEpsilon) {
    return getRemainingBudget(entity) >= requiredEpsilon;
  }

  /// Consumes privacy budget for a given entity.
  bool consumeBudget(String entity, double epsilon) {
    final remaining = getRemainingBudget(entity);
    if (remaining < epsilon) {
      _consumedBudget[entity] = getMaxBudget(entity);
      return false;
    }
    _consumedBudget[entity] = getConsumedBudget(entity) + epsilon;
    return true;
  }

  /// Resets consumed budget for a specific entity.
  void resetBudget(String entity) {
    _consumedBudget[entity] = 0.0;
  }

  /// Resets consumed budget for all entities.
  void resetAllBudgets() {
    _consumedBudget.clear();
  }

  /// Generates zero-mean Laplace noise L(0, b) with scale b = sensitivity / epsilon.
  /// Uses inverse transform sampling: X = -sgn(u) * b * ln(1 - 2|u|).
  double generateLaplaceNoise({double? epsilon, double? sensitivity}) {
    if (!isNoiseEnabled) return 0.0;

    final eps = epsilon ?? defaultEpsilon;
    final sens = sensitivity ?? defaultSensitivity;
    if (eps <= 0) return 0.0;

    final scale = sens / eps;

    // Uniform sample in (-0.5, 0.5) excluding 0 and boundaries
    double u = _random.nextDouble() - 0.5;
    while (u == 0.0 || u <= -0.5 || u >= 0.5) {
      u = _random.nextDouble() - 0.5;
    }

    final sgn = u < 0 ? -1.0 : 1.0;
    return -sgn * scale * log(1.0 - 2.0 * u.abs());
  }

  /// Applies calibrated zero-mean Laplace noise to an integer count,
  /// rounds the result, and enforces a non-negative floor (clamping at 0).
  int applyLaplaceNoiseToInt(
    int value, {
    double? epsilon,
    double? sensitivity,
    String entity = 'daily_brief',
  }) {
    if (!isNoiseEnabled) {
      return value < 0 ? 0 : value;
    }

    final eps = epsilon ?? defaultEpsilon;
    final sens = sensitivity ?? defaultSensitivity;

    consumeBudget(entity, eps);

    final noise = generateLaplaceNoise(epsilon: eps, sensitivity: sens);
    final noisyValue = (value + noise).round();

    // Enforce non-negative floor constraint
    return noisyValue < 0 ? 0 : noisyValue;
  }

  /// Routes daily interaction statistics through local differential privacy transformation.
  DailyBriefEntry transformDailyBrief(
    DailyBriefEntry entry, {
    double? epsilon,
    String entity = 'daily_brief',
  }) {
    final eps = epsilon ?? defaultEpsilon;
    // Guaranteed privacy budget epsilon <= 1.0
    final noiseEps = eps <= 1.0 ? eps : 1.0;

    return entry.copyWith(
      notificationsReviewed: applyLaplaceNoiseToInt(
        entry.notificationsReviewed,
        epsilon: noiseEps,
        entity: '$entity:notificationsReviewed',
      ),
      actionsCompleted: applyLaplaceNoiseToInt(
        entry.actionsCompleted,
        epsilon: noiseEps,
        entity: '$entity:actionsCompleted',
      ),
      calendarEventsCreated: applyLaplaceNoiseToInt(
        entry.calendarEventsCreated,
        epsilon: noiseEps,
        entity: '$entity:calendarEventsCreated',
      ),
      remindersCreated: applyLaplaceNoiseToInt(
        entry.remindersCreated,
        epsilon: noiseEps,
        entity: '$entity:remindersCreated',
      ),
      archivedCount: applyLaplaceNoiseToInt(
        entry.archivedCount,
        epsilon: noiseEps,
        entity: '$entity:archivedCount',
      ),
    );
  }

  /// Quantizes a timestamp to a 15-minute epoch boundary.
  DateTime quantizeTimestamp(DateTime dt, {int intervalMinutes = 15}) {
    if (!isQuantizationEnabled) return dt;

    final intervalMs = intervalMinutes * 60 * 1000;
    final ms = dt.millisecondsSinceEpoch;
    final quantizedMs = (ms ~/ intervalMs) * intervalMs;
    return DateTime.fromMillisecondsSinceEpoch(quantizedMs, isUtc: dt.isUtc);
  }

  /// Quantizes a nullable timestamp to a 15-minute epoch boundary.
  DateTime? quantizeNullableTimestamp(DateTime? dt, {int intervalMinutes = 15}) {
    if (dt == null) return null;
    return quantizeTimestamp(dt, intervalMinutes: intervalMinutes);
  }

  /// Quantizes session duration in seconds using bounded step intervals.
  int quantizeDuration(int durationSeconds, {int stepSeconds = 900}) {
    if (durationSeconds <= 0) return 0;
    if (!isQuantizationEnabled || stepSeconds <= 1) return durationSeconds;

    final steps = (durationSeconds / stepSeconds).round();
    final result = steps * stepSeconds;
    return result < 0 ? 0 : result;
  }

  /// Quantizes interruption counts using bounded step intervals.
  int quantizeInterruptions(int interruptions, {int stepSize = 1}) {
    if (interruptions <= 0) return 0;
    if (!isQuantizationEnabled || stepSize <= 1) return interruptions;

    final steps = (interruptions / stepSize).round();
    final result = steps * stepSize;
    return result < 0 ? 0 : result;
  }

  /// Sanitizes focus session records prior to database insertion or update.
  FocusSessionEntry sanitizeFocusSession(
    FocusSessionEntry entry, {
    int timeWindowMinutes = 15,
    int durationStepSeconds = 900,
    int interruptionStepSize = 1,
  }) {
    final quantizedStart = quantizeTimestamp(
      entry.sessionStart,
      intervalMinutes: timeWindowMinutes,
    );
    final quantizedEnd = quantizeNullableTimestamp(
      entry.sessionEnd,
      intervalMinutes: timeWindowMinutes,
    );

    int quantizedDur = entry.duration;
    if (quantizedEnd != null) {
      final diff = quantizedEnd.difference(quantizedStart).inSeconds;
      quantizedDur = diff < 0 ? 0 : quantizeDuration(diff, stepSeconds: durationStepSeconds);
    } else if (entry.duration > 0) {
      quantizedDur = quantizeDuration(entry.duration, stepSeconds: durationStepSeconds);
    }

    final quantizedInter = quantizeInterruptions(
      entry.interruptions,
      stepSize: interruptionStepSize,
    );

    return FocusSessionEntry(
      id: entry.id,
      sessionStart: quantizedStart,
      sessionEnd: quantizedEnd,
      interruptions: quantizedInter,
      completion: entry.completion,
      duration: quantizedDur,
    );
  }
}
