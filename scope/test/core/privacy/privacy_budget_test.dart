import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/dp_telemetry_service.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  late AttentionDatabase db;
  late PrivacyBudgetManager manager;
  late DpTelemetryService dpService;

  setUp(() async {
    db = AttentionDatabase.inMemory();
    manager = PrivacyBudgetManager(dao: db.privacyBudgetDao, defaultMaxEpsilon: 2.0);
    await manager.initialize();
    dpService = DpTelemetryService(privacyBudgetManager: manager);
  });

  tearDown(() async {
    await db.close();
  });

  group('PrivacyBudgetManager Ledger Tests', () {
    test('Initial budget starts at default max epsilon (2.0)', () {
      expect(manager.getMaxEpsilon(), equals(2.0));
      expect(manager.getConsumedEpsilon(), equals(0.0));
      expect(manager.getRemainingEpsilon(), equals(2.0));
      expect(manager.isBudgetExhausted(), isFalse);
    });

    test('Consuming budget updates ledger state and persists in SQLite', () async {
      final success = await manager.tryConsumeBudget(0.5);
      expect(success, isTrue);
      expect(manager.getConsumedEpsilon(), closeTo(0.5, 0.001));
      expect(manager.getRemainingEpsilon(), closeTo(1.5, 0.001));

      // Re-instantiate manager using same DB to verify SQLite persistence across app restarts
      final newManager = PrivacyBudgetManager(dao: db.privacyBudgetDao, defaultMaxEpsilon: 2.0);
      await newManager.initialize();
      expect(newManager.getRemainingEpsilon(), closeTo(1.5, 0.001));
      expect(newManager.getConsumedEpsilon(), closeTo(0.5, 0.001));
    });

    test('Consuming more budget than remaining returns false and keeps state', () async {
      await manager.tryConsumeBudget(1.8);
      expect(manager.getRemainingEpsilon(), closeTo(0.2, 0.001));

      final failed = await manager.tryConsumeBudget(0.5);
      expect(failed, isFalse);
      expect(manager.getRemainingEpsilon(), closeTo(0.2, 0.001));
    });

    test('Resetting daily budget restores full max epsilon', () async {
      await manager.tryConsumeBudget(2.0);
      expect(manager.isBudgetExhausted(), isTrue);

      await manager.resetDailyBudget();
      expect(manager.isBudgetExhausted(), isFalse);
      expect(manager.getRemainingEpsilon(), equals(2.0));
    });
  });

  group('DpTelemetryService Sensitivity Clipping & Laplace Noise Tests', () {
    test('Laplace noise sampling execution overhead is under 5 milliseconds per query', () {
      final sw = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        dpService.sampleLaplaceNoise(sensitivity: 10.0, epsilon: 0.1);
      }
      sw.stop();

      // 100 queries execute well under 5ms (typically < 1ms)
      expect(sw.elapsedMilliseconds, lessThan(5));
    });

    test('Sensitivity clipping bounds telemetry input parameters prior to noise addition', () async {
      final oversizedSessions = [
        FocusSessionEntry(
          id: 1,
          sessionStart: DateTime.now().subtract(const Duration(hours: 3)),
          sessionEnd: DateTime.now(),
          duration: 15000, // Unclipped: 15,000s (> 7,200s bound)
          interruptions: 50, // Unclipped: 50 (> 20 bound)
          completion: true,
        ),
      ];

      final result = await dpService.queryFocusSessionMetrics(oversizedSessions, epsilonCost: 0.2);
      expect(result.isNoisy, isTrue);
      expect(result.isBudgetExhausted, isFalse);
      
      // Verification: Total duration was sensitivity-clipped to max 7,200s before Laplace noise addition
      // So noisy duration should be centered around ~7,200, not 15,000
      expect(result.data.totalDurationSeconds, lessThan(12000));
      expect(result.data.totalInterruptions, lessThan(40));
    });

    test('Exhausted budget transitions smoothly to generalized bucketed ranges without error', () async {
      // Exhaust the privacy budget completely
      await manager.tryConsumeBudget(2.0);
      expect(manager.isBudgetExhausted(), isTrue);

      final sessions = [
        FocusSessionEntry(
          id: 1,
          sessionStart: DateTime.now().subtract(const Duration(minutes: 25)),
          sessionEnd: DateTime.now(),
          duration: 1500,
          interruptions: 4,
          completion: true,
        ),
      ];

      final focusRes = await dpService.queryFocusSessionMetrics(sessions, epsilonCost: 0.2);
      expect(focusRes.isBudgetExhausted, isTrue);
      expect(focusRes.consumedEpsilon, equals(0.0));
      expect(focusRes.bucketedRanges, isNotNull);
      expect(focusRes.bucketedRanges!['duration'], equals('15 – 30 mins'));
      expect(focusRes.bucketedRanges!['interruptions'], equals('3 – 5 interruptions'));

      final hourlyRes = await dpService.queryHourlyVolume(List.filled(24, 10));
      expect(hourlyRes.isBudgetExhausted, isTrue);

      final overviewRes = await dpService.queryOverviewStats(
        totalCaptured: 18,
        needsActionCount: 4,
        completedTodayCount: 12,
        avgLatencyMs: 120,
      );
      expect(overviewRes.isBudgetExhausted, isTrue);
      expect(overviewRes.bucketedRanges!['totalCaptured'], equals('16 – 30'));
      expect(overviewRes.bucketedRanges!['needsActionCount'], equals('1 – 5'));
    });
  });
}
