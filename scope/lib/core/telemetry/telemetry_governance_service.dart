import 'dart:math' as math;

/// Service managing telemetry governance, 15-minute epoch quantization,
/// duration/interruption quantization, differential privacy Laplace noise injection,
/// and privacy budget tracking.
class TelemetryGovernanceService {
  final double maxEpsilon;
  final double defaultDelta;
  final Map<String, double> _consumedEpsilonByEntity = {};

  TelemetryGovernanceService({
    this.maxEpsilon = 2.0,
    this.defaultDelta = 1e-5,
  });

  /// Quantizes an epoch timestamp in milliseconds to 15-minute boundaries (default: 15 mins).
  static int quantizeTimestamp(int timestampMs, {int intervalMinutes = 15}) {
    if (timestampMs <= 0) return 0;
    final intervalMs = intervalMinutes * 60 * 1000;
    return (timestampMs ~/ intervalMs) * intervalMs;
  }

  /// Quantizes duration in seconds to standard bucket size (default: 60s / 1 min).
  static int quantizeDuration(int seconds, {int bucketSizeSeconds = 60}) {
    if (seconds <= 0) return 0;
    return (seconds ~/ bucketSizeSeconds) * bucketSizeSeconds;
  }

  /// Quantizes interruption count to step size (default: step of 1).
  static int quantizeInterruptions(int count, {int step = 1}) {
    if (count <= 0) return 0;
    return (count ~/ step) * step;
  }


  /// Generates zero-mean Laplace noise L(0, scale) where scale = sensitivity / epsilon.
  /// Uses the inverse CDF method:
  /// U ~ Uniform(-0.5, 0.5)
  /// Noise = -scale * sgn(U) * ln(1 - 2|U|)
  static double generateLaplaceNoise({
    double sensitivity = 1.0,
    double epsilon = 0.5,
    math.Random? random,
  }) {
    if (epsilon <= 0) return 0.0;
    final scale = sensitivity / epsilon;
    final rng = random ?? math.Random();

    // Uniform random value in (0, 1) exclusive to avoid log(0)
    double u = rng.nextDouble();
    while (u <= 0.0 || u >= 1.0) {
      u = rng.nextDouble();
    }

    final centered = u - 0.5;
    final sgn = centered < 0 ? -1.0 : 1.0;
    final noise = -scale * sgn * math.log(1.0 - 2.0 * centered.abs());
    return noise;
  }

  /// Injects Laplace noise into a numeric value and clamps to a non-negative number.
  static int addNoisyCount(
    int value, {
    double sensitivity = 1.0,
    double epsilon = 0.5,
    math.Random? random,
  }) {
    final noise = generateLaplaceNoise(
      sensitivity: sensitivity,
      epsilon: epsilon,
      random: random,
    );
    final noisyValue = (value + noise).round();
    return math.max(0, noisyValue);
  }

  /// Applies differential privacy Laplace noise to daily brief stats with non-negative clamping.
  Map<String, int> applyDifferentialPrivacyToDailyBrief({
    required int notificationsReviewed,
    required int actionsCompleted,
    required int calendarEventsCreated,
    required int remindersCreated,
    required int archivedCount,
    double sensitivity = 1.0,
    double epsilon = 0.5,
    math.Random? random,
  }) {
    return {
      'notificationsReviewed': addNoisyCount(
        notificationsReviewed,
        sensitivity: sensitivity,
        epsilon: epsilon,
        random: random,
      ),
      'actionsCompleted': addNoisyCount(
        actionsCompleted,
        sensitivity: sensitivity,
        epsilon: epsilon,
        random: random,
      ),
      'calendarEventsCreated': addNoisyCount(
        calendarEventsCreated,
        sensitivity: sensitivity,
        epsilon: epsilon,
        random: random,
      ),
      'remindersCreated': addNoisyCount(
        remindersCreated,
        sensitivity: sensitivity,
        epsilon: epsilon,
        random: random,
      ),
      'archivedCount': addNoisyCount(
        archivedCount,
        sensitivity: sensitivity,
        epsilon: epsilon,
        random: random,
      ),
    };
  }

  /// Returns remaining privacy budget for a given entity.
  double getRemainingBudget(String entity) {
    final consumed = _consumedEpsilonByEntity[entity] ?? 0.0;
    return math.max(0.0, maxEpsilon - consumed);
  }

  /// Checks if entity has sufficient privacy budget remaining for [epsilonNeeded].
  bool canConsumeBudget(String entity, double epsilonNeeded) {
    return getRemainingBudget(entity) >= epsilonNeeded;
  }

  /// Consumes privacy budget for [entity]. Returns true if successful, false if budget exceeded.
  bool consumeBudget(String entity, double epsilonNeeded) {
    if (!canConsumeBudget(entity, epsilonNeeded)) {
      return false;
    }
    final current = _consumedEpsilonByEntity[entity] ?? 0.0;
    _consumedEpsilonByEntity[entity] = current + epsilonNeeded;
    return true;
  }

  /// Resets consumed privacy budget for an entity (e.g., after epoch rotation).
  void resetBudget(String entity) {
    _consumedEpsilonByEntity[entity] = 0.0;
  }
}
