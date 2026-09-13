import 'package:flutter/foundation.dart';

/// Custom exception thrown when the differential privacy budget is exhausted.
class PrivacyBudgetExhaustedException implements Exception {
  final String message;
  final double requestedEpsilon;
  final double remainingEpsilon;

  const PrivacyBudgetExhaustedException({
    required this.message,
    required this.requestedEpsilon,
    required this.remainingEpsilon,
  });

  @override
  String toString() =>
      'PrivacyBudgetExhaustedException: $message (Requested: $requestedEpsilon, Remaining: $remainingEpsilon)';
}

/// Tracks differential privacy budget consumption per training epoch window.
class PrivacyBudgetTracker {
  /// Maximum epsilon budget allowed per epoch window.
  final double maxEpsilon;

  /// Target delta bound ($\delta \le 10^{-5}$).
  final double targetDelta;

  /// Current accumulated epsilon consumption.
  double _consumedEpsilon;

  /// Timestamp marking the start of the active epoch window.
  DateTime _epochStart;

  PrivacyBudgetTracker({
    this.maxEpsilon = 2.0,
    this.targetDelta = 1e-5,
    double initialConsumedEpsilon = 0.0,
    DateTime? epochStart,
  })  : _consumedEpsilon = initialConsumedEpsilon,
        _epochStart = epochStart ?? DateTime.now();

  /// Gets the total consumed epsilon.
  double get consumedEpsilon => _consumedEpsilon;

  /// Gets the remaining available epsilon budget.
  double get remainingEpsilon => (maxEpsilon - _consumedEpsilon).clamp(0.0, maxEpsilon);

  /// Gets the timestamp for the current epoch window.
  DateTime get epochStart => _epochStart;

  /// Indicates if the total privacy budget has been exhausted.
  bool get isBudgetExhausted => _consumedEpsilon >= (maxEpsilon - 1e-9);

  /// Checks whether a given epsilon allocation can be safely consumed without exceeding budget.
  bool canConsume(double stepEpsilon) {
    if (stepEpsilon <= 0) return true;
    return (_consumedEpsilon + stepEpsilon) <= (maxEpsilon + 1e-9);
  }

  /// Deducts epsilon allocation from the active budget or throws if budget exhausted.
  void consume(double stepEpsilon) {
    if (stepEpsilon <= 0) return;

    if (!canConsume(stepEpsilon)) {
      debugPrint(
        'PrivacyBudgetTracker: Budget exhausted! Cannot allocate epsilon = $stepEpsilon '
        '(Consumed: $_consumedEpsilon / $maxEpsilon)',
      );
      throw PrivacyBudgetExhaustedException(
        message: 'Maximum privacy budget exceeded for active epoch window',
        requestedEpsilon: stepEpsilon,
        remainingEpsilon: remainingEpsilon,
      );
    }

    _consumedEpsilon += stepEpsilon;
    debugPrint(
      'PrivacyBudgetTracker: Consumed epsilon = $stepEpsilon. Total: $_consumedEpsilon / $maxEpsilon',
    );
  }

  /// Resets the epoch window and clears consumed budget counter.
  void resetEpoch() {
    _consumedEpsilon = 0.0;
    _epochStart = DateTime.now();
    debugPrint('PrivacyBudgetTracker: Reset epoch window at $_epochStart.');
  }

  /// Converts tracking state to a JSON-serializable map for persistence.
  Map<String, dynamic> toJson() => {
        'max_epsilon': maxEpsilon,
        'target_delta': targetDelta,
        'consumed_epsilon': _consumedEpsilon,
        'epoch_start': _epochStart.toIso8601String(),
      };

  /// Restores tracker instance from a JSON map.
  factory PrivacyBudgetTracker.fromJson(Map<String, dynamic> json) {
    return PrivacyBudgetTracker(
      maxEpsilon: (json['max_epsilon'] as num?)?.toDouble() ?? 2.0,
      targetDelta: (json['target_delta'] as num?)?.toDouble() ?? 1e-5,
      initialConsumedEpsilon: (json['consumed_epsilon'] as num?)?.toDouble() ?? 0.0,
      epochStart: json['epoch_start'] != null
          ? DateTime.tryParse(json['epoch_start'] as String)
          : null,
    );
  }
}
