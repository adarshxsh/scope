import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:scope/database/attention_database.dart';

/// Result wrapper for privacy budget evaluated queries.
class PrivacyQueryResult<T> {
  final T value;
  final String bucketInterval;
  final bool isFallback;
  final double remainingBudget;
  final double consumedEpsilon;

  PrivacyQueryResult({
    required this.value,
    required this.bucketInterval,
    required this.isFallback,
    required this.remainingBudget,
    required this.consumedEpsilon,
  });

  @override
  String toString() {
    return 'PrivacyQueryResult(value: $value, bucketInterval: $bucketInterval, isFallback: $isFallback, remainingBudget: ${remainingBudget.toStringAsFixed(2)})';
  }
}

/// Aggregate stats for focus sessions after budget-aware noise evaluation.
class FocusSessionAggregateStats {
  final int totalDurationSeconds;
  final int totalInterruptions;
  final int sessionCount;

  FocusSessionAggregateStats({
    required this.totalDurationSeconds,
    required this.totalInterruptions,
    required this.sessionCount,
  });
}

/// Centralized differential privacy engine with privacy budget accounting.
class PrivacyBudgetEngine extends ChangeNotifier {
  PrivacyBudgetEngine({
    AttentionDatabase? db,
    double defaultTargetEpsilon = 1.0,
    math.Random? random,
  })  : _db = db,
        _targetEpsilon = defaultTargetEpsilon,
        _random = random ?? math.Random();

  final AttentionDatabase? _db;
  double _targetEpsilon;
  double _consumedEpsilon = 0.0;
  String _currentEpochDate = _getTodayEpochDate();
  final math.Random _random;

  bool _isInitialized = false;
  Future<void>? _initFuture;

  double get targetEpsilon => _targetEpsilon;
  double get consumedEpsilon => _consumedEpsilon;
  double get remainingBudget => math.max(0.0, _targetEpsilon - _consumedEpsilon);
  bool get isBudgetDepleted => _consumedEpsilon >= _targetEpsilon;
  String get currentEpochDate => _currentEpochDate;

  static String _getTodayEpochDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> initialize() async {
    _initFuture ??= _doInitialize();
    return _initFuture;
  }

  Future<void> _doInitialize() async {
    if (_isInitialized) return;
    _currentEpochDate = _getTodayEpochDate();
    if (_db != null) {
      try {
        final entry = await _db!.privacyBudgetDao.getBudgetForDate(_currentEpochDate);
        if (entry != null) {
          _targetEpsilon = entry.targetEpsilon;
          _consumedEpsilon = entry.consumedEpsilon;
        } else {
          await _db!.privacyBudgetDao.insertOrUpdateBudget(PrivacyBudgetEntry(
            id: 0,
            epochDate: _currentEpochDate,
            targetEpsilon: _targetEpsilon,
            consumedEpsilon: 0.0,
          ));
          _consumedEpsilon = 0.0;
        }
      } catch (_) {
        // Fallback for memory or DB errors
      }
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// Clips input value `val` to defined sensitivity bounds [minBound, maxBound].
  double clip(double val, double minBound, double maxBound) {
    return val.clamp(minBound, maxBound);
  }

  /// Clips integer value to [minBound, maxBound].
  int clipInt(int val, int minBound, int maxBound) {
    return val.clamp(minBound, maxBound);
  }

  /// Samples calibrated Laplace noise Lap(0, scale) where scale = sensitivity / epsilon.
  double sampleLaplace(double sensitivity, double epsilon) {
    if (epsilon <= 0) return 0.0;
    final scale = sensitivity / epsilon;
    // Draw uniform u in (-0.5, 0.5)
    double u = _random.nextDouble() - 0.5;
    while (u == 0 || u == 0.5 || u == -0.5) {
      u = _random.nextDouble() - 0.5;
    }
    final sgn = u < 0 ? -1.0 : 1.0;
    return -scale * sgn * math.log(1.0 - 2.0 * u.abs());
  }

  /// Evaluates budget and applies Laplace noise or coarsened bucket fallback atomically.
  /// Deducts epsilonQuery if budget is available.
  Future<PrivacyQueryResult<double>> evaluateDoubleQuery({
    required double rawValue,
    required double sensitivity,
    double epsilonQuery = 0.1,
    double minVal = 0.0,
    double maxVal = double.infinity,
  }) async {
    await initialize();
    _checkEpochRollover();

    final clippedValue = clip(rawValue, minVal, maxVal);

    if (_consumedEpsilon + epsilonQuery <= _targetEpsilon + 1e-9) {
      // Deduct budget atomically
      _consumedEpsilon += epsilonQuery;
      await _persistBudget();

      final noise = sampleLaplace(sensitivity, epsilonQuery);
      final noisyVal = clip(clippedValue + noise, minVal, maxVal);

      notifyListeners();
      return PrivacyQueryResult<double>(
        value: noisyVal,
        bucketInterval: _formatCoarsenedBucket(noisyVal),
        isFallback: false,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    } else {
      // Budget depleted - apply coarsened bucket fallback
      return PrivacyQueryResult<double>(
        value: _coarsenValue(clippedValue),
        bucketInterval: _formatCoarsenedBucket(clippedValue),
        isFallback: true,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    }
  }

  /// Evaluates budget and applies Laplace noise or coarsened bucket fallback for integer metrics.
  Future<PrivacyQueryResult<int>> evaluateIntQuery({
    required int rawValue,
    required double sensitivity,
    double epsilonQuery = 0.1,
    int minVal = 0,
    int maxVal = 2147483647,
  }) async {
    await initialize();
    _checkEpochRollover();

    final clippedValue = clipInt(rawValue, minVal, maxVal);

    if (_consumedEpsilon + epsilonQuery <= _targetEpsilon + 1e-9) {
      _consumedEpsilon += epsilonQuery;
      await _persistBudget();

      final noise = sampleLaplace(sensitivity, epsilonQuery);
      final noisyVal = (clippedValue + noise).round().clamp(minVal, maxVal);

      notifyListeners();
      return PrivacyQueryResult<int>(
        value: noisyVal,
        bucketInterval: _formatCoarsenedBucket(noisyVal.toDouble()),
        isFallback: false,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    } else {
      final coarsened = _coarsenValue(clippedValue.toDouble()).round().clamp(minVal, maxVal);
      return PrivacyQueryResult<int>(
        value: coarsened,
        bucketInterval: _formatCoarsenedBucket(clippedValue.toDouble()),
        isFallback: true,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    }
  }

  /// Evaluates budget for a vector/list of integer metrics (e.g., 24-hour distribution).
  Future<PrivacyQueryResult<List<int>>> evaluateIntListQuery({
    required List<int> rawValues,
    required double sensitivity,
    double epsilonQuery = 0.1,
    int minVal = 0,
    int maxVal = 2147483647,
  }) async {
    await initialize();
    _checkEpochRollover();

    if (_consumedEpsilon + epsilonQuery <= _targetEpsilon + 1e-9) {
      _consumedEpsilon += epsilonQuery;
      await _persistBudget();

      final result = <int>[];
      final perElemEpsilon = epsilonQuery / math.max(1, rawValues.length);
      for (final val in rawValues) {
        final clipped = clipInt(val, minVal, maxVal);
        final noise = sampleLaplace(sensitivity, perElemEpsilon);
        result.add((clipped + noise).round().clamp(minVal, maxVal));
      }

      notifyListeners();
      return PrivacyQueryResult<List<int>>(
        value: result,
        bucketInterval: 'Laplace Noise Injected',
        isFallback: false,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    } else {
      final result = <int>[];
      for (final val in rawValues) {
        final clipped = clipInt(val, minVal, maxVal);
        result.add(_coarsenValue(clipped.toDouble()).round().clamp(minVal, maxVal));
      }

      return PrivacyQueryResult<List<int>>(
        value: result,
        bucketInterval: 'Coarsened Bucket Fallback',
        isFallback: true,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    }
  }

  /// Evaluates budget for a Map of integer metric counts (e.g. priorities or focus areas).
  Future<PrivacyQueryResult<Map<K, int>>> evaluateIntMapQuery<K>({
    required Map<K, int> rawMap,
    required double sensitivity,
    double epsilonQuery = 0.1,
    int minVal = 0,
    int maxVal = 2147483647,
  }) async {
    await initialize();
    _checkEpochRollover();

    if (_consumedEpsilon + epsilonQuery <= _targetEpsilon + 1e-9) {
      _consumedEpsilon += epsilonQuery;
      await _persistBudget();

      final resultMap = <K, int>{};
      final numKeys = math.max(1, rawMap.length);
      final perKeyEpsilon = epsilonQuery / numKeys;
      for (final entry in rawMap.entries) {
        final clipped = clipInt(entry.value, minVal, maxVal);
        final noise = sampleLaplace(sensitivity, perKeyEpsilon);
        resultMap[entry.key] = (clipped + noise).round().clamp(minVal, maxVal);
      }

      notifyListeners();
      return PrivacyQueryResult<Map<K, int>>(
        value: resultMap,
        bucketInterval: 'Laplace Noise Injected',
        isFallback: false,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    } else {
      final resultMap = <K, int>{};
      for (final entry in rawMap.entries) {
        final clipped = clipInt(entry.value, minVal, maxVal);
        resultMap[entry.key] = _coarsenValue(clipped.toDouble()).round().clamp(minVal, maxVal);
      }

      return PrivacyQueryResult<Map<K, int>>(
        value: resultMap,
        bucketInterval: 'Coarsened Bucket Fallback',
        isFallback: true,
        remainingBudget: remainingBudget,
        consumedEpsilon: _consumedEpsilon,
      );
    }
  }

  void _checkEpochRollover() {
    final today = _getTodayEpochDate();
    if (today != _currentEpochDate) {
      _currentEpochDate = today;
      _consumedEpsilon = 0.0;
    }
  }

  Future<void> _persistBudget() async {
    if (_db == null) return;
    try {
      await _db!.privacyBudgetDao.updateConsumedEpsilon(_currentEpochDate, _consumedEpsilon);
    } catch (_) {}
  }

  double _coarsenValue(double val) {
    if (val < 5) return (val / 2.0).roundToDouble() * 2.0;
    if (val < 25) return (val / 5.0).round() * 5.0;
    if (val < 100) return (val / 10.0).round() * 10.0;
    return (val / 25.0).round() * 25.0;
  }

  String _formatCoarsenedBucket(double val) {
    if (val < 5) return '< 5';
    if (val < 10) return '5–10';
    if (val < 25) return '10–25';
    if (val < 50) return '25–50';
    if (val < 100) return '50–100';
    return '100+';
  }

  /// Resets daily budget (useful for testing and admin actions).
  Future<void> resetBudget({double? targetEpsilon}) async {
    if (targetEpsilon != null) {
      _targetEpsilon = targetEpsilon;
    }
    _consumedEpsilon = 0.0;
    _currentEpochDate = _getTodayEpochDate();
    await _persistBudget();
    notifyListeners();
  }
}
