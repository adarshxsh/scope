import 'package:flutter/foundation.dart';
import 'package:scope/core/federated/differential_privacy.dart';

/// Represents a single privacy-preserving audit log record.
class FLAuditLogEntry {
  final String roundId;
  final DateTime timestamp;
  final int sampleCount;
  final double initialGradientNorm;
  final double clippedGradientNorm;
  final double noiseScale;
  final double privacyEpsilonSpent;
  final double privacyDelta;
  final String status;
  final String details;

  const FLAuditLogEntry({
    required this.roundId,
    required this.timestamp,
    required this.sampleCount,
    required this.initialGradientNorm,
    required this.clippedGradientNorm,
    required this.noiseScale,
    required this.privacyEpsilonSpent,
    required this.privacyDelta,
    required this.status,
    required this.details,
  });

  Map<String, dynamic> toJson() => {
        'roundId': roundId,
        'timestamp': timestamp.toIso8601String(),
        'sampleCount': sampleCount,
        'initialGradientNorm': initialGradientNorm,
        'clippedGradientNorm': clippedGradientNorm,
        'noiseScale': noiseScale,
        'privacyEpsilonSpent': privacyEpsilonSpent,
        'privacyDelta': privacyDelta,
        'status': status,
        'details': details,
      };

  @override
  String toString() {
    return 'FLAuditLogEntry(roundId: $roundId, status: $status, samples: $sampleCount, eps: ${privacyEpsilonSpent.toStringAsFixed(4)})';
  }
}

/// Result payload returned by Federated Learning local update operations.
class FLUpdateResult {
  final bool success;
  final String roundId;
  final List<double>? updatedWeights;
  final FLAuditLogEntry auditLog;
  final String? errorMessage;

  const FLUpdateResult({
    required this.success,
    required this.roundId,
    this.updatedWeights,
    required this.auditLog,
    this.errorMessage,
  });
}

/// On-device Privacy-Preserving Federated Learning Manager for SCOPE (AttentionOS).
/// Enforces Differential Privacy, gradient clipping, PII redaction, audit logging,
/// and fallback error recovery.
class FederatedLearningManager extends ChangeNotifier {
  final DifferentialPrivacy dp;
  final double learningRate;
  final int maxAuditLogEntries;

  List<double> _baseWeights;
  int _completedRounds = 0;
  final List<FLAuditLogEntry> _auditLogs = [];

  FederatedLearningManager({
    List<double>? initialWeights,
    DifferentialPrivacy? dp,
    this.learningRate = 0.01,
    this.maxAuditLogEntries = 100,
  })  : dp = dp ?? DifferentialPrivacy(),
        _baseWeights = initialWeights ?? List.filled(63, 0.0);

  List<double> get currentWeights => List.unmodifiable(_baseWeights);
  int get completedRounds => _completedRounds;
  List<FLAuditLogEntry> get auditLogs => List.unmodifiable(_auditLogs);

  /// Calculates total cumulative privacy budget (epsilon) consumed so far.
  double get cumulativeEpsilonSpent => dp.calculateEpsilonSpent(_completedRounds);

  /// Computes a local Differential-Private Federated Learning update over local samples.
  /// Enforces L2 norm clipping, Gaussian noise addition, budget checks, PII scrubbing,
  /// and fallback recovery paths.
  FLUpdateResult computeLocalUpdate({
    required List<List<double>> features,
    required List<double> targets,
    required String roundId,
    double? customClipNorm,
    double? customNoiseMultiplier,
  }) {
    final now = DateTime.now();
    final sanitizedRoundId = DifferentialPrivacy.sanitizePII(roundId);

    // 1. Validate inputs
    if (features.isEmpty || targets.isEmpty || features.length != targets.length) {
      final entry = FLAuditLogEntry(
        roundId: sanitizedRoundId,
        timestamp: now,
        sampleCount: features.length,
        initialGradientNorm: 0.0,
        clippedGradientNorm: 0.0,
        noiseScale: 0.0,
        privacyEpsilonSpent: cumulativeEpsilonSpent,
        privacyDelta: dp.config.targetDelta,
        status: 'fallback_invalid_inputs',
        details: DifferentialPrivacy.sanitizePII('Failed: Empty or mismatched feature/target arrays.'),
      );
      _addAuditLog(entry);
      return FLUpdateResult(
        success: false,
        roundId: sanitizedRoundId,
        auditLog: entry,
        errorMessage: 'Invalid or mismatched input samples.',
      );
    }

    // 2. Check Privacy Budget
    if (cumulativeEpsilonSpent >= dp.config.maxPrivacyBudgetEpsilon) {
      final entry = FLAuditLogEntry(
        roundId: sanitizedRoundId,
        timestamp: now,
        sampleCount: features.length,
        initialGradientNorm: 0.0,
        clippedGradientNorm: 0.0,
        noiseScale: 0.0,
        privacyEpsilonSpent: cumulativeEpsilonSpent,
        privacyDelta: dp.config.targetDelta,
        status: 'fallback_privacy_budget_exceeded',
        details: DifferentialPrivacy.sanitizePII(
            'Aborted: Maximum privacy budget epsilon (${dp.config.maxPrivacyBudgetEpsilon}) reached.'),
      );
      _addAuditLog(entry);
      return FLUpdateResult(
        success: false,
        roundId: sanitizedRoundId,
        auditLog: entry,
        errorMessage: 'Privacy budget limit reached. FL local training paused.',
      );
    }

    try {
      final numFeatures = _baseWeights.length;
      final numSamples = features.length;

      // 3. Compute local gradient vector
      // Loss: L = 1/N * sum (w * x_i - y_i)^2
      // Grad: dL/dw = 2/N * sum (w * x_i - y_i) * x_i
      final rawGradient = List<double>.filled(numFeatures, 0.0);

      for (int i = 0; i < numSamples; i++) {
        final x = features[i];
        final y = targets[i];

        if (x.length != numFeatures) {
          throw ArgumentError('Feature dimension mismatch. Expected $numFeatures, got ${x.length}');
        }

        if (y.isNaN || y.isInfinite) {
          throw ArgumentError('Target value contains non-finite numerical value (NaN or Infinity)');
        }

        // Dot product
        double pred = 0.0;
        for (int j = 0; j < numFeatures; j++) {
          final xVal = x[j];
          if (xVal.isNaN || xVal.isInfinite) {
            throw ArgumentError('Feature component at index $j contains non-finite value');
          }
          pred += _baseWeights[j] * xVal;
        }

        final error = pred - y;
        for (int j = 0; j < numFeatures; j++) {
          rawGradient[j] += (2.0 / numSamples) * error * x[j];
        }
      }

      // 4. Validate raw gradient
      final initialNorm = dp.calculateL2Norm(rawGradient);

      // 5. Differential Privacy Guardrails: L2 Norm Clipping & Noise Addition
      final effectiveClipNorm = customClipNorm ?? dp.config.clipNorm;
      final effectiveNoiseMult = customNoiseMultiplier ?? dp.config.noiseMultiplier;

      final clippedGrad = dp.clipVector(rawGradient, effectiveClipNorm);
      final clippedNorm = dp.calculateL2Norm(clippedGrad);

      final noiseScale = effectiveNoiseMult * effectiveClipNorm;
      final dpGradient = dp.addGaussianNoise(clippedGrad, noiseScale);

      // 6. Update local model weights with DP-protected gradient
      final updatedWeights = List<double>.filled(numFeatures, 0.0);
      for (int j = 0; j < numFeatures; j++) {
        final newWeight = _baseWeights[j] - (learningRate * dpGradient[j]);
        if (newWeight.isNaN || newWeight.isInfinite) {
          throw StateError('Gradient step resulted in non-finite weight at index $j');
        }
        updatedWeights[j] = newWeight;
      }

      // Apply updated weights and increment round counter
      _baseWeights = updatedWeights;
      _completedRounds++;

      final auditEntry = FLAuditLogEntry(
        roundId: sanitizedRoundId,
        timestamp: now,
        sampleCount: numSamples,
        initialGradientNorm: initialNorm,
        clippedGradientNorm: clippedNorm,
        noiseScale: noiseScale,
        privacyEpsilonSpent: cumulativeEpsilonSpent,
        privacyDelta: dp.config.targetDelta,
        status: 'success',
        details: DifferentialPrivacy.sanitizePII(
            'Local update completed with DP protection (samples: $numSamples, noise: ${noiseScale.toStringAsFixed(4)}).'),
      );

      _addAuditLog(auditEntry);
      notifyListeners();

      return FLUpdateResult(
        success: true,
        roundId: sanitizedRoundId,
        updatedWeights: List.unmodifiable(_baseWeights),
        auditLog: auditEntry,
      );
    } catch (e) {
      // 7. Fallback Error Recovery Path
      final fallbackEntry = FLAuditLogEntry(
        roundId: sanitizedRoundId,
        timestamp: now,
        sampleCount: features.length,
        initialGradientNorm: 0.0,
        clippedGradientNorm: 0.0,
        noiseScale: 0.0,
        privacyEpsilonSpent: cumulativeEpsilonSpent,
        privacyDelta: dp.config.targetDelta,
        status: 'fallback_error',
        details: DifferentialPrivacy.sanitizePII('Error recovered safely during local FL round: ${e.toString()}'),
      );

      _addAuditLog(fallbackEntry);
      notifyListeners();

      return FLUpdateResult(
        success: false,
        roundId: sanitizedRoundId,
        auditLog: fallbackEntry,
        errorMessage: DifferentialPrivacy.sanitizePII(e.toString()),
      );
    }
  }

  void _addAuditLog(FLAuditLogEntry entry) {
    _auditLogs.add(entry);
    if (_auditLogs.length > maxAuditLogEntries) {
      _auditLogs.removeAt(0);
    }
  }

  /// Clears audit logs and memory.
  void clearAuditLogs() {
    _auditLogs.clear();
    notifyListeners();
  }

  /// Resets round history and privacy budget counter.
  void resetPrivacyBudget() {
    _completedRounds = 0;
    notifyListeners();
  }
}
