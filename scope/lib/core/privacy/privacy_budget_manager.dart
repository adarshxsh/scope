import 'package:flutter/foundation.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// Manages client-side local privacy budget tracking cumulative epsilon privacy loss in SQLite.
class PrivacyBudgetManager extends ChangeNotifier {
  final PrivacyBudgetDao _dao;
  final double defaultMaxEpsilon;

  PrivacyBudgetEntry? _todayEntry;
  String _currentDateStr = '';

  PrivacyBudgetManager({
    required PrivacyBudgetDao dao,
    this.defaultMaxEpsilon = 2.0,
  }) : _dao = dao;

  String _formatDate(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Initializes or syncs the today budget ledger record.
  Future<void> initialize() async {
    await checkAndResetDailyBudget();
  }

  /// Checks if the local date has changed and automatically resets or initializes today's budget ledger.
  Future<PrivacyBudgetEntry> checkAndResetDailyBudget() async {
    final today = _formatDate(DateTime.now());
    if (_todayEntry != null && _currentDateStr == today) {
      return _todayEntry!;
    }

    _currentDateStr = today;
    var entry = await _dao.getBudgetForDate(today);
    if (entry == null) {
      entry = PrivacyBudgetEntry(
        id: 0,
        date: today,
        consumedEpsilon: 0.0,
        maxEpsilon: defaultMaxEpsilon,
        lastUpdated: DateTime.now(),
      );
      await _dao.insertOrUpdate(entry);
    }
    _todayEntry = entry;
    notifyListeners();
    return _todayEntry!;
  }

  /// Gets the remaining epsilon privacy budget for today.
  double getRemainingEpsilon() {
    if (_todayEntry == null) return defaultMaxEpsilon;
    final remaining = _todayEntry!.maxEpsilon - _todayEntry!.consumedEpsilon;
    return remaining < 0 ? 0.0 : remaining;
  }

  /// Gets total max budget for today.
  double getMaxEpsilon() {
    return _todayEntry?.maxEpsilon ?? defaultMaxEpsilon;
  }

  /// Gets total consumed budget for today.
  double getConsumedEpsilon() {
    return _todayEntry?.consumedEpsilon ?? 0.0;
  }

  /// Returns true if the daily privacy budget is exhausted (remaining <= 0).
  bool isBudgetExhausted() {
    return getRemainingEpsilon() <= 0.000001;
  }

  /// Attempts to consume [cost] epsilon from today's budget.
  /// If remaining budget is sufficient, updates local SQLite ledger and returns true.
  /// Otherwise, returns false.
  Future<bool> tryConsumeBudget(double cost) async {
    await checkAndResetDailyBudget();
    final remaining = getRemainingEpsilon();
    if (remaining >= cost - 1e-9) {
      final newConsumed = _todayEntry!.consumedEpsilon + cost;
      await _dao.updateConsumedEpsilon(_currentDateStr, newConsumed);
      _todayEntry = _todayEntry!.copyWith(
        consumedEpsilon: newConsumed,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Manually or scheduled reset of today's privacy budget.
  Future<void> resetDailyBudget({double? maxEpsilon}) async {
    final today = _formatDate(DateTime.now());
    _currentDateStr = today;
    final targetMax = maxEpsilon ?? defaultMaxEpsilon;
    await _dao.resetBudget(today, maxEpsilon: targetMax);
    _todayEntry = await _dao.getBudgetForDate(today);
    notifyListeners();
  }
}
