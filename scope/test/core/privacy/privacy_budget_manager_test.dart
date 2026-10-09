import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/core/state/notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LaplaceNoise Distribution Tests', () {
    test('sample generates zero noise when scale is zero', () {
      final noise = LaplaceNoise.sample(0.0);
      expect(noise, equals(0.0));
    });

    test('sample mean is centered near zero for large sample size', () {
      final rng = Random(42);
      const scale = 2.0;
      const samplesCount = 10000;
      double sum = 0.0;

      for (int i = 0; i < samplesCount; i++) {
        sum += LaplaceNoise.sample(scale, random: rng);
      }

      final mean = sum / samplesCount;
      expect(mean.abs(), lessThan(0.1));
    });

    test('smaller epsilon produces larger noise magnitude (variance)', () {
      final rng1 = Random(123);
      final rng2 = Random(123);

      const sensitivity = 1.0;
      const smallEpsilon = 0.01; // High privacy -> large noise
      const largeEpsilon = 10.0; // Low privacy -> small noise

      final scaleSmallEps = LaplaceNoise.scaleFromSensitivity(sensitivity, smallEpsilon);
      final scaleLargeEps = LaplaceNoise.scaleFromSensitivity(sensitivity, largeEpsilon);

      expect(scaleSmallEps, equals(100.0));
      expect(scaleLargeEps, equals(0.1));

      double absSumSmall = 0.0;
      double absSumLarge = 0.0;
      const count = 1000;

      for (int i = 0; i < count; i++) {
        absSumSmall += LaplaceNoise.sample(scaleSmallEps, random: rng1).abs();
        absSumLarge += LaplaceNoise.sample(scaleLargeEps, random: rng2).abs();
      }

      expect(absSumSmall / count, greaterThan(absSumLarge / count * 10));
    });

    test('scaleFromSensitivity throws ArgumentError for non-positive epsilon', () {
      expect(() => LaplaceNoise.scaleFromSensitivity(1.0, 0.0), throwsArgumentError);
      expect(() => LaplaceNoise.scaleFromSensitivity(1.0, -0.5), throwsArgumentError);
    });
  });

  group('PrivacyBudgetManager Ledger & Deduction Logic', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager manager;

    setUp(() {
      db = AttentionDatabase.inMemory();
      manager = PrivacyBudgetManager(
        db: db,
        dailyEpsilonCap: 0.5,
        monthlyEpsilonCap: 5.0,
        defaultEpsilonPerQuery: 0.1,
        random: Random(42),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('initial ledger state shows zero epsilon spent', () async {
      final status = await manager.getStatus();
      expect(status.spentToday, equals(0.0));
      expect(status.spentThisMonth, equals(0.0));
      expect(status.remainingDaily, equals(0.5));
      expect(status.remainingMonthly, equals(5.0));
      expect(status.isDailyExhausted, isFalse);
      expect(status.isExhausted, isFalse);
    });

    test('deducts epsilon on query execution and updates ledger in database', () async {
      final result = await manager.executeNoisedQuery<int>(
        exactQuery: () async => 42,
        sensitivity: 1.0,
        epsilon: 0.1,
      );

      expect(result.exactValue, equals(42));
      expect(result.epsilonDeducted, equals(0.1));
      expect(result.isBudgetExhausted, isFalse);

      final status = await manager.getStatus();
      expect(status.spentToday, closeTo(0.1, 1e-5));
      expect(status.remainingDaily, closeTo(0.4, 1e-5));
    });

    test('multiple queries accumulate spent budget in persistent ledger', () async {
      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 10,
        sensitivity: 1.0,
        epsilon: 0.2,
      );
      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 20,
        sensitivity: 1.0,
        epsilon: 0.2,
      );

      final status = await manager.getStatus();
      expect(status.spentToday, closeTo(0.4, 1e-5));
      expect(status.remainingDaily, closeTo(0.1, 1e-5));
      expect(status.isDailyExhausted, isFalse);
    });

    test('halts reporting and returns coarsened bounds when daily budget is exhausted', () async {
      // Consume full 0.5 budget (0.3 + 0.2)
      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 10,
        sensitivity: 1.0,
        epsilon: 0.3,
      );
      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 10,
        sensitivity: 1.0,
        epsilon: 0.2,
      );

      var status = await manager.getStatus();
      expect(status.isDailyExhausted, isTrue);

      // Subsequent query when budget is exhausted
      final exhaustedResult = await manager.executeNoisedQuery<int>(
        exactQuery: () async => 27,
        sensitivity: 1.0,
        epsilon: 0.1,
        coarseningBucket: 10.0,
      );

      expect(exhaustedResult.isBudgetExhausted, isTrue);
      expect(exhaustedResult.epsilonDeducted, equals(0.0));
      expect(exhaustedResult.coarsenedBounds, equals('[20 - 30]'));
      expect(exhaustedResult.exactValue, equals(27));

      // Ledger count should not increase spent budget beyond cap
      status = await manager.getStatus();
      expect(status.spentToday, closeTo(0.5, 1e-5));
    });

    test('resets budget counters on different date key (simulating local midnight)', () async {
      final now = DateTime(2026, 9, 11, 23, 30);
      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 100,
        sensitivity: 1.0,
        epsilon: 0.4,
        now: now,
      );

      var statusToday = await manager.getStatus(now);
      expect(statusToday.spentToday, closeTo(0.4, 1e-5));

      // Next day after midnight
      final nextDay = DateTime(2026, 9, 12, 0, 5);
      var statusNextDay = await manager.getStatus(nextDay);
      expect(statusNextDay.spentToday, equals(0.0));
      expect(statusNextDay.remainingDaily, equals(0.5));
      expect(statusNextDay.isDailyExhausted, isFalse);
    });

    test('vector query applies noise across element array and deducts total epsilon', () async {
      final results = await manager.executeVectorQuery(
        exactQuery: () async => [5, 12, 0, 8],
        sensitivityPerElement: 1.0,
        totalEpsilon: 0.2,
      );

      expect(results.length, equals(4));
      expect(results.every((r) => !r.isBudgetExhausted), isTrue);

      final status = await manager.getStatus();
      expect(status.spentToday, closeTo(0.2, 1e-5));
    });
  });

  group('FocusSession and DailyBrief DAO Sensitivity Clipping & DP Queries', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager manager;

    setUp(() {
      db = AttentionDatabase.inMemory();
      manager = PrivacyBudgetManager(
        db: db,
        dailyEpsilonCap: 1.0,
        random: Random(100),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('focus duration applies sensitivity clipping (120s max per session) and Laplace noise', () async {
      final now = DateTime.now();
      // Insert session with 300s duration (exceeding 120s sensitivity clip)
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 0,
        sessionStart: now,
        sessionEnd: now.add(const Duration(seconds: 300)),
        interruptions: 2,
        completion: true,
        duration: 300,
      ));

      final noisedResult = await db.focusSessionDao.getNoisedTotalFocusDuration(
        manager,
        sensitivity: 120.0,
        epsilon: 0.1,
      );

      // Exact query clipped duration is 120s (not 300s)
      expect(noisedResult.exactValue, equals(120));
      expect(noisedResult.isBudgetExhausted, isFalse);
    });

    test('focus interruptions applies sensitivity clipping (5 max per session) and Laplace noise', () async {
      final now = DateTime.now();
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 0,
        sessionStart: now,
        sessionEnd: now.add(const Duration(seconds: 60)),
        interruptions: 20, // Exceeds 5 max clip
        completion: true,
        duration: 60,
      ));

      final noisedResult = await db.focusSessionDao.getNoisedFocusInterruptions(
        manager,
        sensitivity: 5.0,
        epsilon: 0.1,
      );

      expect(noisedResult.exactValue, equals(5));
      expect(noisedResult.isBudgetExhausted, isFalse);
    });

    test('daily brief reviewed count returns noised count', () async {
      const dateStr = '2026-09-11';
      await db.dailyBriefDao.incrementStats(dateStr, reviewed: 15);

      final result = await db.dailyBriefDao.getNoisedReviewedCount(
        manager,
        dateStr,
        epsilon: 0.1,
      );

      expect(result.exactValue, equals(15));
      expect(result.isBudgetExhausted, isFalse);
    });
  });

  group('NotificationController DP Integration Tests', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager manager;
    late NotificationController controller;

    setUp(() {
      db = AttentionDatabase.inMemory();
      manager = PrivacyBudgetManager(
        db: db,
        dailyEpsilonCap: 1.0,
        random: Random(99),
      );
      controller = NotificationController(
        privacyBudgetManager: manager,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('controller analytical query methods draw budget and return DP noised results', () async {
      final priorityDist = await controller.getNoisedPriorityDistribution(epsilon: 0.1);
      expect(priorityDist.keys, containsAll(['critical', 'high', 'medium', 'low']));

      final totalCaptured = await controller.getNoisedTotalCapturedCount(epsilon: 0.1);
      expect(totalCaptured.isBudgetExhausted, isFalse);

      final hourlyVol = await controller.getNoisedHourlyVolume(epsilon: 0.1);
      expect(hourlyVol.length, equals(24));

      final focusAreas = await controller.getNoisedFocusAreaCounts(epsilon: 0.1);
      expect(focusAreas.keys.length, equals(FocusArea.values.length));

      final status = await controller.getPrivacyBudgetStatus();
      expect(status.spentToday, greaterThan(0.0));
      expect(status.remainingDaily, lessThan(1.0));
    });
  });
}
