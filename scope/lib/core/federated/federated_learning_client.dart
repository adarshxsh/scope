import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:scope/core/federated/federated_types.dart';
import 'package:scope/core/federated/privacy_budget_tracker.dart';

/// Client-side DP-SGD Federated Learning engine for computing, clipping, obfuscating,
/// and buffering local model gradient updates.
class FederatedLearningClient {
  static FederatedLearningClient? _instance;

  final PrivacyBudgetTracker privacyBudgetTracker;
  final double clippingThresholdC;
  final double defaultEpsilonStep;
  final double targetDelta;
  final SyncGuardrails syncGuardrails;
  final int maxBufferSize;

  final List<ClientGradientUpdate> _bufferedUpdates = [];
  bool _isWifiConnected = true;
  bool _isCharging = true;

  FederatedLearningClient({
    PrivacyBudgetTracker? privacyBudgetTracker,
    this.clippingThresholdC = 1.0,
    this.defaultEpsilonStep = 0.1,
    this.targetDelta = 1e-5,
    this.syncGuardrails = const SyncGuardrails(),
    this.maxBufferSize = 100,
  }) : privacyBudgetTracker = privacyBudgetTracker ?? PrivacyBudgetTracker();

  static FederatedLearningClient get instance =>
      _instance ??= FederatedLearningClient();

  /// Gets unmodifiable list of buffered gradient updates.
  List<ClientGradientUpdate> get bufferedUpdates =>
      List.unmodifiable(_bufferedUpdates);

  /// Sets device connection states for guardrail enforcement.
  void setDeviceState({required bool isWifiConnected, required bool isCharging}) {
    _isWifiConnected = isWifiConnected;
    _isCharging = isCharging;
  }

  /// Evaluates whether sync conditions are met per guardrails and network state.
  bool canSync({bool? isWifiConnected, bool? isCharging}) {
    final wifi = isWifiConnected ?? _isWifiConnected;
    final charging = isCharging ?? _isCharging;

    if (syncGuardrails.requireUnmeteredWifi && !wifi) return false;
    if (syncGuardrails.requireCharging && !charging) return false;
    return true;
  }

  /// Computes a differentially private gradient update given input 63-D feature vector,
  /// predicted score, and target user score.
  ClientGradientUpdate computeGradientUpdate({
    required List<double> featureVector,
    required double predictedScore,
    required double targetScore,
    double? epsilonStep,
    double? customClippingC,
    bool useGaussianNoise = true,
    Random? rng,
  }) {
    final stopwatch = Stopwatch()..start();

    if (featureVector.length != 63) {
      throw ArgumentError(
        'Feature vector must contain exactly 63 dimensions (got ${featureVector.length})',
      );
    }

    if (predictedScore.isNaN ||
        predictedScore.isInfinite ||
        targetScore.isNaN ||
        targetScore.isInfinite) {
      throw ArgumentError('Predicted score and target score must be finite numbers');
    }

    for (int i = 0; i < featureVector.length; i++) {
      if (featureVector[i].isNaN || featureVector[i].isInfinite) {
        throw ArgumentError(
          'Feature vector contains non-finite value at index $i: ${featureVector[i]}',
        );
      }
    }

    final epsilon = epsilonStep ?? defaultEpsilonStep;
    final clippingC = customClippingC ?? clippingThresholdC;

    if (epsilon <= 0 || epsilon.isNaN || epsilon.isInfinite) {
      throw ArgumentError('Epsilon step must be a positive finite number');
    }

    if (clippingC <= 0 || clippingC.isNaN || clippingC.isInfinite) {
      throw ArgumentError('Clipping threshold C must be a positive finite number');
    }

    // 1. Check Privacy Budget
    if (!privacyBudgetTracker.canConsume(epsilon)) {
      throw PrivacyBudgetExhaustedException(
        message: 'Cannot compute gradient update: Privacy budget limit reached.',
        requestedEpsilon: epsilon,
        remainingEpsilon: privacyBudgetTracker.remainingEpsilon,
      );
    }

    // 2. Compute Raw Loss Gradient: dL/dw_i = (predictedScore - targetScore) * x_i
    final errorDelta = predictedScore - targetScore;
    final rawGradient = List<double>.generate(
      63,
      (i) => errorDelta * featureVector[i],
    );

    // 3. Compute L2 Norm
    double sumSquares = 0.0;
    for (int i = 0; i < 63; i++) {
      sumSquares += rawGradient[i] * rawGradient[i];
    }
    final rawL2Norm = sqrt(sumSquares);

    // 4. L2 Norm Gradient Clipping
    final clippedGradient = List<double>.filled(63, 0.0);
    double clippedL2Norm = rawL2Norm;

    if (rawL2Norm > clippingC && rawL2Norm > 0) {
      final scaleFactor = clippingC / rawL2Norm;
      for (int i = 0; i < 63; i++) {
        clippedGradient[i] = rawGradient[i] * scaleFactor;
      }
      clippedL2Norm = clippingC;
    } else {
      for (int i = 0; i < 63; i++) {
        clippedGradient[i] = rawGradient[i];
      }
    }

    // 5. Calibrated DP Noise Injection
    final dpGradient = List<double>.filled(63, 0.0);
    final random = rng ?? Random();

    if (useGaussianNoise) {
      // Gaussian noise parameter: sigma = (C * sqrt(2 * ln(1.25 / delta))) / epsilon
      final sigma = (clippingC * sqrt(2.0 * log(1.25 / targetDelta))) / epsilon;
      for (int i = 0; i < 63; i++) {
        final noise = _generateGaussianNoise(sigma, random);
        dpGradient[i] = clippedGradient[i] + noise;
      }
    } else {
      // Laplace noise parameter: b = C / epsilon
      final b = clippingC / epsilon;
      for (int i = 0; i < 63; i++) {
        final noise = _generateLaplaceNoise(b, random);
        dpGradient[i] = clippedGradient[i] + noise;
      }
    }

    // 6. Deduct Privacy Budget
    privacyBudgetTracker.consume(epsilon);

    stopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        'FederatedLearningClient: Computed DP-SGD update in ${stopwatch.elapsedMicroseconds} us. '
        'L2 Norm raw: ${rawL2Norm.toStringAsFixed(4)} -> clipped: ${clippedL2Norm.toStringAsFixed(4)}. '
        'Epsilon used: $epsilon.',
      );
    }

    final update = ClientGradientUpdate(
      updateId: 'dp-update-${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(10000)}',
      gradientDelta: dpGradient,
      l2NormBeforeClipping: rawL2Norm,
      l2NormAfterClipping: clippedL2Norm,
      epsilonUsed: epsilon,
      deltaUsed: targetDelta,
      timestamp: DateTime.now(),
    );

    // Buffer update with FIFO eviction to respect memory quota
    while (_bufferedUpdates.length >= maxBufferSize && _bufferedUpdates.isNotEmpty) {
      _bufferedUpdates.removeAt(0);
    }
    _bufferedUpdates.add(update);
    return update;
  }

  /// Helper generating Box-Muller normal random variate N(0, sigma^2).
  double _generateGaussianNoise(double sigma, Random rng) {
    double u1 = rng.nextDouble();
    while (u1 <= 1e-15) {
      u1 = rng.nextDouble(); // avoid log(0)
    }
    final u2 = rng.nextDouble();
    final z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
    return z0 * sigma;
  }

  /// Helper generating Laplace random variate Lap(0, b).
  double _generateLaplaceNoise(double b, Random rng) {
    double u = rng.nextDouble() - 0.5;
    while (u == 0.0) {
      u = rng.nextDouble() - 0.5;
    }
    final sgn = u > 0 ? 1.0 : -1.0;
    return -b * sgn * log(1.0 - 2.0 * u.abs());
  }

  /// Exports and flushes all buffered gradient updates for federated round transmission.
  List<ClientGradientUpdate> exportAndClearBufferedUpdates({
    bool enforceGuardrails = true,
    bool? isWifiConnected,
    bool? isCharging,
  }) {
    if (enforceGuardrails && !canSync(isWifiConnected: isWifiConnected, isCharging: isCharging)) {
      debugPrint('FederatedLearningClient: Sync skipped due to guardrails constraint.');
      return [];
    }

    final updates = List<ClientGradientUpdate>.from(_bufferedUpdates);
    _bufferedUpdates.clear();
    return updates;
  }

  /// Clears internal update buffer.
  void clearBuffer() {
    _bufferedUpdates.clear();
  }
}
