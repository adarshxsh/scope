import 'package:equatable/equatable.dart';

/// Represents an anonymized, differentially private gradient update payload ready for federated aggregation.
class ClientGradientUpdate extends Equatable {
  /// Anonymized identifier for client session batch (no PII or user IDs).
  final String updateId;

  /// 63-dimensional clipped and noise-added gradient vector delta.
  final List<double> gradientDelta;

  /// L2 norm of raw gradient before clipping.
  final double l2NormBeforeClipping;

  /// L2 norm of gradient after clipping to threshold C.
  final double l2NormAfterClipping;

  /// Privacy budget epsilon expended for this update.
  final double epsilonUsed;

  /// Privacy budget delta parameter.
  final double deltaUsed;

  /// Timestamp when update was computed.
  final DateTime timestamp;

  /// Number of feedback samples incorporated into gradient.
  final int sampleCount;

  const ClientGradientUpdate({
    required this.updateId,
    required this.gradientDelta,
    required this.l2NormBeforeClipping,
    required this.l2NormAfterClipping,
    required this.epsilonUsed,
    required this.deltaUsed,
    required this.timestamp,
    this.sampleCount = 1,
  });

  Map<String, dynamic> toJson() => {
        'update_id': updateId,
        'gradient_delta': gradientDelta,
        'l2_norm_before': l2NormBeforeClipping,
        'l2_norm_after': l2NormAfterClipping,
        'epsilon_used': epsilonUsed,
        'delta_used': deltaUsed,
        'timestamp': timestamp.toIso8601String(),
        'sample_count': sampleCount,
      };

  factory ClientGradientUpdate.fromJson(Map<String, dynamic> json) {
    return ClientGradientUpdate(
      updateId: json['update_id'] as String,
      gradientDelta: (json['gradient_delta'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      l2NormBeforeClipping: (json['l2_norm_before'] as num).toDouble(),
      l2NormAfterClipping: (json['l2_norm_after'] as num).toDouble(),
      epsilonUsed: (json['epsilon_used'] as num).toDouble(),
      deltaUsed: (json['delta_used'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sampleCount: json['sample_count'] as int? ?? 1,
    );
  }

  @override
  List<Object?> get props => [
        updateId,
        gradientDelta,
        l2NormBeforeClipping,
        l2NormAfterClipping,
        epsilonUsed,
        deltaUsed,
        timestamp,
        sampleCount,
      ];
}

/// Device state guardrails configuration for executing federated synchronization.
class SyncGuardrails extends Equatable {
  final bool requireUnmeteredWifi;
  final bool requireCharging;

  const SyncGuardrails({
    this.requireUnmeteredWifi = true,
    this.requireCharging = true,
  });

  @override
  List<Object?> get props => [requireUnmeteredWifi, requireCharging];
}
