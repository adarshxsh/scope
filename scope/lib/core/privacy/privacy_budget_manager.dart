import 'dart:math';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// Helper for sampling Laplace noise Lap(mu=0, b).
class LaplaceNoise {
  /// Generates a Laplace noise sample with scale parameter b = sensitivity / epsilon.
  /// Uses inverse transform sampling.
  static double sample(double scale, {Random? random}) {
    if (scale <= 0) return 0.0;
    final rng = random ?? Random();

    // Draw uniform variable u in (0, 1)
    double u = rng.nextDouble();
    // Clamp u to avoid log(0) or log(1) undefined results
    u = u.clamp(1e-12, 1.0 - 1e-12);

    if (u < 0.5) {
      return scale * log(2.0 * u);
    } else {
      return -scale * log(2.0 * (1.0 - u));
    }
  }

  /// Calculates scale b = delta_f / epsilon.
  static double scaleFromSensitivity(double sensitivity, double epsilon) {
    if (epsilon <= 0) throw ArgumentError('Epsilon must be greater than zero.');
    return sensitivity / epsilon;
  }
}

/// Represents the result of an analytical telemetry query passed through differential privacy.
class NoisedQueryResult<T extends num> {
  final T exactValue;
  final double noisedValue;
  final double epsilonDeducted;
  final bool isBudgetExhausted;
  final String? coarsenedBounds;

  const NoisedQueryResult({
    required this.exactValue,
    required this.noisedValue,
    required this.epsilonDeducted,
    required this.isBudgetExhausted,
    this.coarsenedBounds,
  });

  /// Rounded integer representation of noised value.
  int get noisedInt => noisedValue.round();
}

/// Status snapshot of the privacy budget.
class PrivacyBudgetStatus {
  final double dailyCap;
  final double monthlyCap;
  final double spentToday;
  final double spentThisMonth;
  final double remainingDaily;
  final double remainingMonthly;
  final bool isDailyExhausted;
  final bool isMonthlyExhausted;

  const PrivacyBudgetStatus({
    required this.dailyCap,
    required this.monthlyCap,
    required this.spentToday,
    required this.spentThisMonth,
    required this.remainingDaily,
    required this.remainingMonthly,
    required this.isDailyExhausted,
    required this.isMonthlyExhausted,
  });

  bool get isExhausted => isDailyExhausted || isMonthlyExhausted;
}

/// Client-side Differential Privacy Budget Manager.
class PrivacyBudgetManager {
  final AttentionDatabase? _db;
  final double dailyEpsilonCap;
  final double monthlyEpsilonCap;
  final double defaultEpsilonPerQuery;
  final Random? _random;

  // In-memory fallback tracking when db is not provided
  double _inMemorySpentToday = 0.0;
  double _inMemorySpentMonth = 0.0;
  String _lastInMemoryDateKey = '';
  String _lastInMemoryMonthKey = '';

  PrivacyBudgetManager({
    AttentionDatabase? db,
    this.dailyEpsilonCap = 1.0,
    this.monthlyEpsilonCap = 10.0,
    this.defaultEpsilonPerQuery = 0.1,
    Random? random,
  })  : _db = db,
        _random = random;

  PrivacyLedgerDao? get _ledgerDao {
    if (_db == null) return null;
    try {
      return _db.privacyLedgerDao;
    } catch (_) {
      return null;
    }
  }

  /// Returns today's date key in YYYY-MM-DD format.
  String _todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Returns current month key in YYYY-MM format.
  String _monthKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  /// Fetches current privacy budget status from the persistent ledger or in-memory fallback.
  Future<PrivacyBudgetStatus> getStatus([DateTime? now]) async {
    final dateKey = _todayKey(now);
    final monthKey = _monthKey(now);

    double spentToday = 0.0;
    double spentMonth = 0.0;

    final dao = _ledgerDao;
    if (dao != null) {
      spentToday = await dao.getEpsilonSpentForDate(dateKey);
      spentMonth = await dao.getEpsilonSpentForMonth(monthKey);
    } else {
      if (_lastInMemoryDateKey != dateKey) {
        _inMemorySpentToday = 0.0;
        _lastInMemoryDateKey = dateKey;
      }
      if (_lastInMemoryMonthKey != monthKey) {
        _inMemorySpentMonth = 0.0;
        _lastInMemoryMonthKey = monthKey;
      }
      spentToday = _inMemorySpentToday;
      spentMonth = _inMemorySpentMonth;
    }

    final remainingDaily = (dailyEpsilonCap - spentToday).clamp(0.0, dailyEpsilonCap);
    final remainingMonthly = (monthlyEpsilonCap - spentMonth).clamp(0.0, monthlyEpsilonCap);

    return PrivacyBudgetStatus(
      dailyCap: dailyEpsilonCap,
      monthlyCap: monthlyEpsilonCap,
      spentToday: spentToday,
      spentThisMonth: spentMonth,
      remainingDaily: remainingDaily,
      remainingMonthly: remainingMonthly,
      isDailyExhausted: spentToday >= dailyEpsilonCap,
      isMonthlyExhausted: spentMonth >= monthlyEpsilonCap,
    );
  }

  /// Executes an analytical query with differential privacy Laplace noise.
  /// If budget is available, deducts epsilon and adds noise.
  /// If budget is exhausted, halts fine-grained reporting and returns coarsened bounds.
  Future<NoisedQueryResult<T>> executeNoisedQuery<T extends num>({
    required Future<T> Function() exactQuery,
    required double sensitivity,
    double? epsilon,
    double delta = 0.0,
    bool clipToZero = true,
    double coarseningBucket = 10.0,
    DateTime? now,
  }) async {
    final qEpsilon = epsilon ?? defaultEpsilonPerQuery;
    final status = await getStatus(now);

    final dateKey = _todayKey(now);
    final monthKey = _monthKey(now);

    // Check if remaining budget is insufficient
    if (status.remainingDaily < qEpsilon || status.remainingMonthly < qEpsilon) {
      final exact = await exactQuery();
      // Graceful degradation: calculate coarsened bounds
      final val = exact.toDouble();
      final bucketInt = coarseningBucket.toInt() > 0 ? coarseningBucket.toInt() : 10;
      final lower = (val / bucketInt).floor() * bucketInt;
      final upper = lower + bucketInt;
      final coarsenedValue = (lower + upper) / 2.0;

      return NoisedQueryResult<T>(
        exactValue: exact,
        noisedValue: coarsenedValue,
        epsilonDeducted: 0.0,
        isBudgetExhausted: true,
        coarsenedBounds: '[$lower - $upper]',
      );
    }

    // Budget available: execute exact query and add Laplace noise
    final exact = await exactQuery();
    final scale = LaplaceNoise.scaleFromSensitivity(sensitivity, qEpsilon);
    final noise = LaplaceNoise.sample(scale, random: _random);
    var noised = exact.toDouble() + noise;

    if (clipToZero && noised < 0) {
      noised = 0.0;
    }

    // Record privacy budget consumption in persistent ledger
    final dao = _ledgerDao;
    if (dao != null) {
      await dao.recordQueryConsumption(dateKey, qEpsilon, delta);
    } else {
      if (_lastInMemoryDateKey != dateKey) {
        _inMemorySpentToday = 0.0;
        _lastInMemoryDateKey = dateKey;
      }
      if (_lastInMemoryMonthKey != monthKey) {
        _inMemorySpentMonth = 0.0;
        _lastInMemoryMonthKey = monthKey;
      }
      _inMemorySpentToday += qEpsilon;
      _inMemorySpentMonth += qEpsilon;
    }

    return NoisedQueryResult<T>(
      exactValue: exact,
      noisedValue: noised,
      epsilonDeducted: qEpsilon,
      isBudgetExhausted: false,
    );
  }

  /// Applies Laplace noise to a list of numeric analytical values (e.g., hourly volume array)
  /// consuming a total budget of [epsilon] split across items or deducting per query.
  Future<List<NoisedQueryResult<num>>> executeVectorQuery({
    required Future<List<num>> Function() exactQuery,
    required double sensitivityPerElement,
    double? totalEpsilon,
    DateTime? now,
  }) async {
    final exactList = await exactQuery();
    if (exactList.isEmpty) return [];

    final totalEps = totalEpsilon ?? defaultEpsilonPerQuery;
    final perElementEpsilon = totalEps / exactList.length;

    final status = await getStatus(now);
    final dateKey = _todayKey(now);
    final monthKey = _monthKey(now);

    if (status.remainingDaily < totalEps || status.remainingMonthly < totalEps) {
      return exactList.map((exact) {
        final val = exact.toDouble();
        final lower = (val / 10.0).floor() * 10;
        final upper = lower + 10;
        return NoisedQueryResult<num>(
          exactValue: exact,
          noisedValue: lower.toDouble(),
          epsilonDeducted: 0.0,
          isBudgetExhausted: true,
          coarsenedBounds: '[$lower - $upper]',
        );
      }).toList();
    }

    final scale = LaplaceNoise.scaleFromSensitivity(sensitivityPerElement, perElementEpsilon);
    final results = <NoisedQueryResult<num>>[];

    for (final exact in exactList) {
      final noise = LaplaceNoise.sample(scale, random: _random);
      var noised = exact.toDouble() + noise;
      if (noised < 0) noised = 0.0;

      results.add(NoisedQueryResult<num>(
        exactValue: exact,
        noisedValue: noised,
        epsilonDeducted: perElementEpsilon,
        isBudgetExhausted: false,
      ));
    }

    final dao = _ledgerDao;
    if (dao != null) {
      await dao.recordQueryConsumption(dateKey, totalEps, 0.0);
    } else {
      if (_lastInMemoryDateKey != dateKey) {
        _inMemorySpentToday = 0.0;
        _lastInMemoryDateKey = dateKey;
      }
      if (_lastInMemoryMonthKey != monthKey) {
        _inMemorySpentMonth = 0.0;
        _lastInMemoryMonthKey = monthKey;
      }
      _inMemorySpentToday += totalEps;
      _inMemorySpentMonth += totalEps;
    }

    return results;
  }
}
