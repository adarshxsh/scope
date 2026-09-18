import 'dart:math' as math;

/// Configurable anonymization levels for telemetry governance.
enum TelemetryAnonymizationLevel {
  /// Raw analytics with no noise injection or k-anonymity suppression.
  off,

  /// Standard privacy: k-anonymity (k=3), moderate Laplace noise (epsilon=1.0).
  standard,

  /// Strict differential privacy: k-anonymity (k=5), strong Laplace noise (epsilon=0.5).
  strict,
}

/// Container for daily brief interaction statistics.
class GovernedDailyBriefStats {
  final int notificationsReviewed;
  final int actionsCompleted;
  final int calendarEventsCreated;
  final int remindersCreated;
  final int archivedCount;

  const GovernedDailyBriefStats({
    required this.notificationsReviewed,
    required this.actionsCompleted,
    required this.calendarEventsCreated,
    required this.remindersCreated,
    required this.archivedCount,
  });
}

/// Application-layer service for telemetry governance.
/// Intercepts analytics queries and enforces:
/// - 15-minute timestamp quantization for focus sessions.
/// - k-anonymity aggregation thresholds for hourly volume metrics.
/// - On-device Laplace noise injection for differential privacy.
class TelemetryGovernanceManager {
  TelemetryAnonymizationLevel _level;
  final math.Random _random;

  TelemetryGovernanceManager({
    TelemetryAnonymizationLevel level = TelemetryAnonymizationLevel.standard,
    math.Random? random,
  })  : _level = level,
        _random = random ?? math.Random();

  TelemetryAnonymizationLevel get level => _level;

  set level(TelemetryAnonymizationLevel newLevel) {
    _level = newLevel;
  }

  /// Quantizes a timestamp to the nearest preceding 15-minute interval.
  DateTime quantizeTimestamp(DateTime time, {int intervalMinutes = 15}) {
    final minute = (time.minute ~/ intervalMinutes) * intervalMinutes;
    return DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      minute,
    );
  }

  /// Quantizes focus session start and end times to 15-minute binned intervals.
  Map<String, dynamic> quantizeFocusSession(DateTime start, DateTime? end) {
    final qStart = quantizeTimestamp(start);
    final qEnd = end != null ? quantizeTimestamp(end) : null;
    final durationMinutes = qEnd != null
        ? qEnd.difference(qStart).inMinutes.clamp(0, 10000)
        : 0;

    return {
      'quantizedStart': qStart,
      'quantizedEnd': qEnd,
      'durationMinutes': durationMinutes,
    };
  }

  /// Generates a Laplace noise sample with mean 0 and scale b = sensitivity / epsilon.
  double _sampleLaplace(double epsilon, {double sensitivity = 1.0}) {
    if (epsilon <= 0) return 0.0;
    final b = sensitivity / epsilon;
    // Uniform variable in (-0.5, 0.5)
    var u = _random.nextDouble() - 0.5;
    // Avoid exact 0.5 or -0.5 to prevent log(0)
    if (u.abs() >= 0.499999) {
      u = 0.499999 * (u < 0 ? -1.0 : 1.0);
    }
    final sign = u < 0 ? -1.0 : 1.0;
    return -b * sign * math.log(1.0 - 2.0 * u.abs());
  }

  /// Injects Laplace noise into an integer count value and clamps to >= 0.
  int addLaplaceNoise(int value, {required double epsilon, double sensitivity = 1.0}) {
    if (_level == TelemetryAnonymizationLevel.off || epsilon <= 0) {
      return value;
    }
    final noise = _sampleLaplace(epsilon, sensitivity: sensitivity);
    final noisyValue = (value + noise).round();
    return math.max(0, noisyValue);
  }

  /// Applies k-anonymity suppression to hourly volume bins.
  /// Bins below kThreshold are suppressed (set to 0).
  List<int> applyKAnonymity(List<int> hourlyVolume, {required int kThreshold}) {
    if (_level == TelemetryAnonymizationLevel.off || kThreshold <= 1) {
      return List<int>.from(hourlyVolume);
    }
    return hourlyVolume.map((count) => count < kThreshold ? 0 : count).toList();
  }

  /// Governs hourly volume distributions using k-anonymity and Laplace noise.
  List<int> processHourlyVolume(List<int> rawHourlyVolume) {
    if (_level == TelemetryAnonymizationLevel.off) {
      return List<int>.from(rawHourlyVolume);
    }

    final kThreshold = _level == TelemetryAnonymizationLevel.strict ? 5 : 3;
    final epsilon = _level == TelemetryAnonymizationLevel.strict ? 0.5 : 1.0;

    // Step 1: k-anonymity suppression
    final kAnonymized = applyKAnonymity(rawHourlyVolume, kThreshold: kThreshold);

    // Step 2: Laplace noise injection on non-suppressed bins
    return kAnonymized.map((count) {
      if (count == 0) return 0;
      return addLaplaceNoise(count, epsilon: epsilon);
    }).toList();
  }

  /// Applies Laplace noise differential privacy to daily brief statistics.
  GovernedDailyBriefStats processDailyBriefStats({
    required int notificationsReviewed,
    required int actionsCompleted,
    required int calendarEventsCreated,
    required int remindersCreated,
    required int archivedCount,
  }) {
    if (_level == TelemetryAnonymizationLevel.off) {
      return GovernedDailyBriefStats(
        notificationsReviewed: notificationsReviewed,
        actionsCompleted: actionsCompleted,
        calendarEventsCreated: calendarEventsCreated,
        remindersCreated: remindersCreated,
        archivedCount: archivedCount,
      );
    }

    final epsilon = _level == TelemetryAnonymizationLevel.strict ? 0.5 : 1.0;

    return GovernedDailyBriefStats(
      notificationsReviewed: addLaplaceNoise(notificationsReviewed, epsilon: epsilon),
      actionsCompleted: addLaplaceNoise(actionsCompleted, epsilon: epsilon),
      calendarEventsCreated: addLaplaceNoise(calendarEventsCreated, epsilon: epsilon),
      remindersCreated: addLaplaceNoise(remindersCreated, epsilon: epsilon),
      archivedCount: addLaplaceNoise(archivedCount, epsilon: epsilon),
    );
  }
}
