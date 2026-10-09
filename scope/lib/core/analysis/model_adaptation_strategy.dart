import 'package:scope/core/analysis/model_audit_logger.dart';

/// User feedback interaction event used for local on-device model adaptation.
class UserFeedbackEvent {
  final DateTime timestamp;
  final String notificationId;
  final String predictedCategory;
  final double predictedScore;
  final String userAction; // 'accepted', 'rejected', 'demoted', 'promoted'
  final String? actualPriority;

  UserFeedbackEvent({
    DateTime? timestamp,
    required this.notificationId,
    required this.predictedCategory,
    required this.predictedScore,
    required this.userAction,
    this.actualPriority,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// On-device model adaptation strategy and drift monitoring controller.
class ModelAdaptationStrategy {
  final List<UserFeedbackEvent> _feedbackHistory = [];
  static const int _historyWindowSize = 50;

  /// Drift threshold for disagreement rate triggering adaptation alerts (default 25%)
  double driftThreshold;

  /// On-device Platt calibration offsets
  double _scoreOffset = 0.0;
  double _scoreMultiplier = 1.0;

  ModelAdaptationStrategy({
    this.driftThreshold = 0.25,
  });

  /// Current calibration offset applied to predictions
  double get scoreOffset => _scoreOffset;

  /// Current calibration multiplier applied to predictions
  double get scoreMultiplier => _scoreMultiplier;

  /// Records user feedback interaction and adjusts on-device calibration.
  void recordFeedback(UserFeedbackEvent feedback) {
    _feedbackHistory.add(feedback);
    if (_feedbackHistory.length > _historyWindowSize) {
      _feedbackHistory.removeAt(0);
    }

    // On-device calibration adjustment
    if (feedback.userAction == 'rejected' || feedback.userAction == 'demoted') {
      _scoreOffset = (_scoreOffset - 0.02).clamp(-0.20, 0.20);
    } else if (feedback.userAction == 'promoted') {
      _scoreOffset = (_scoreOffset + 0.02).clamp(-0.20, 0.20);
    } else if (feedback.userAction == 'accepted') {
      // Gently decay offset back toward 0.0
      _scoreOffset = (_scoreOffset * 0.95);
    }

    final currentDisagreement = disagreementRate;
    final isDrift = isDriftDetected;

    ModelAuditLogger.instance.log(
      'ADAPTATION_APPLIED',
      'Feedback recorded (${feedback.userAction}). Score offset: ${_scoreOffset.toStringAsFixed(3)}, Disagreement rate: ${(currentDisagreement * 100).toStringAsFixed(1)}%.',
      metadata: {
        'action': feedback.userAction,
        'offset': _scoreOffset,
        'multiplier': _scoreMultiplier,
        'disagreementRate': currentDisagreement,
        'isDriftDetected': isDrift,
      },
    );

    if (isDrift) {
      ModelAuditLogger.instance.log(
        'DRIFT_DETECTED',
        'Model drift detected! Disagreement rate ${(currentDisagreement * 100).toStringAsFixed(1)}% exceeds threshold ${(driftThreshold * 100).toStringAsFixed(1)}%.',
      );
    }
  }

  /// Calculates disagreement rate over the recent feedback window.
  double get disagreementRate {
    if (_feedbackHistory.isEmpty) return 0.0;
    final disagreements = _feedbackHistory.where(
      (f) => f.userAction == 'rejected' || f.userAction == 'demoted' || f.userAction == 'promoted',
    ).length;
    return disagreements / _feedbackHistory.length;
  }

  /// Returns whether model drift is detected based on recent user feedback disagreements.
  bool get isDriftDetected {
    if (_feedbackHistory.length < 5) return false;
    return disagreementRate >= driftThreshold;
  }

  /// Applies on-device calibrated score adaptation.
  double applyAdaptation(double rawScore) {
    if (rawScore.isNaN || rawScore.isInfinite) return 0.0;
    final adapted = (rawScore * _scoreMultiplier) + _scoreOffset;
    return adapted.clamp(0.0, 1.0);
  }

  /// Resets calibration offsets and clears feedback history.
  void reset() {
    _scoreOffset = 0.0;
    _scoreMultiplier = 1.0;
    _feedbackHistory.clear();
    ModelAuditLogger.instance.log('ADAPTATION_RESET', 'Adaptation strategy calibration parameters reset.');
  }
}
