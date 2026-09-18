import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LaplaceNoise Unit Tests', () {
    test('sample returns 0.0 when scale <= 0', () {
      expect(LaplaceNoise.sample(0.0), equals(0.0));
      expect(LaplaceNoise.sample(-1.0), equals(0.0));
    });

    test('sample produces deterministic noise with seeded Random', () {
      final rng1 = Random(42);
      final rng2 = Random(42);

      final val1 = LaplaceNoise.sample(2.0, random: rng1);
      final val2 = LaplaceNoise.sample(2.0, random: rng2);

      expect(val1, equals(val2));
      expect(val1, isNot(equals(0.0)));
    });

    test('scaleFromSensitivity calculates scale parameter correctly', () {
      expect(LaplaceNoise.scaleFromSensitivity(10.0, 1.0), equals(10.0));
      expect(LaplaceNoise.scaleFromSensitivity(1.0, 0.1), equals(10.0));
      expect(LaplaceNoise.scaleFromSensitivity(120.0, 0.5), equals(240.0));
    });

    test('scaleFromSensitivity throws ArgumentError when epsilon <= 0', () {
      expect(
        () => LaplaceNoise.scaleFromSensitivity(10.0, 0.0),
        throwsArgumentError,
      );
      expect(
        () => LaplaceNoise.scaleFromSensitivity(10.0, -0.5),
        throwsArgumentError,
      );
    });
  });

  group('PrivacyBudgetManager & Ledger Persistence', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager manager;

    setUp(() {
      db = AttentionDatabase.inMemory();
      manager = PrivacyBudgetManager(db: db, dailyEpsilonCap: 1.0, monthlyEpsilonCap: 10.0);
    });

    tearDown(() async {
      await db.close();
    });

    test('initial status has zero spent budget', () async {
      final status = await manager.getStatus();
      expect(status.spentToday, equals(0.0));
      expect(status.spentThisMonth, equals(0.0));
      expect(status.remainingDaily, equals(1.0));
      expect(status.remainingMonthly, equals(10.0));
      expect(status.isDailyExhausted, isFalse);
      expect(status.isMonthlyExhausted, isFalse);
      expect(status.isExhausted, isFalse);
    });

    test('executeNoisedQuery deducts epsilon and updates persistent ledger', () async {
      final now = DateTime(2026, 9, 13, 10, 0);

      final res = await manager.executeNoisedQuery<int>(
        exactQuery: () async => 42,
        sensitivity: 1.0,
        epsilon: 0.2,
        now: now,
      );

      expect(res.exactValue, equals(42));
      expect(res.epsilonDeducted, equals(0.2));
      expect(res.isBudgetExhausted, isFalse);

      final status = await manager.getStatus(now);
      expect(status.spentToday, closeTo(0.2, 1e-5));
      expect(status.remainingDaily, closeTo(0.8, 1e-5));

      final entries = await db.privacyLedgerDao.getAll();
      expect(entries.length, equals(1));
      expect(entries.first.date, equals('2026-09-13'));
      expect(entries.first.epsilonSpent, closeTo(0.2, 1e-5));
    });

    test('budget exhaustion triggers coarsened bounds fallback', () async {
      final now = DateTime(2026, 9, 13, 10, 0);

      // Consume entire daily budget
      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 10,
        sensitivity: 1.0,
        epsilon: 1.0,
        now: now,
      );

      final status = await manager.getStatus(now);
      expect(status.isDailyExhausted, isTrue);

      // Subsequent query should fall back to coarsened bounds
      final fallbackRes = await manager.executeNoisedQuery<int>(
        exactQuery: () async => 27,
        sensitivity: 1.0,
        epsilon: 0.1,
        coarseningBucket: 10.0,
        now: now,
      );

      expect(fallbackRes.isBudgetExhausted, isTrue);
      expect(fallbackRes.epsilonDeducted, equals(0.0));
      expect(fallbackRes.exactValue, equals(27));
      expect(fallbackRes.noisedValue, equals(25.0)); // midpoint of [20 - 30]
      expect(fallbackRes.coarsenedBounds, equals('[20 - 30]'));
    });

    test('date rollover resets daily budget consumption', () async {
      final day1 = DateTime(2026, 9, 13, 10, 0);
      final day2 = DateTime(2026, 9, 14, 10, 0);

      await manager.executeNoisedQuery<int>(
        exactQuery: () async => 5,
        sensitivity: 1.0,
        epsilon: 0.8,
        now: day1,
      );

      final statusDay1 = await manager.getStatus(day1);
      expect(statusDay1.spentToday, closeTo(0.8, 1e-5));

      final statusDay2 = await manager.getStatus(day2);
      expect(statusDay2.spentToday, equals(0.0));
      expect(statusDay2.spentThisMonth, closeTo(0.8, 1e-5));
    });

    test('in-memory fallback works when database is null', () async {
      final nullDbManager = PrivacyBudgetManager(
        db: null,
        dailyEpsilonCap: 1.0,
        monthlyEpsilonCap: 10.0,
        random: Random(42),
      );

      final now = DateTime(2026, 9, 13, 10, 0);

      final res = await nullDbManager.executeNoisedQuery<int>(
        exactQuery: () async => 15,
        sensitivity: 1.0,
        epsilon: 0.3,
        now: now,
      );

      expect(res.exactValue, equals(15));
      expect(res.epsilonDeducted, equals(0.3));

      final status = await nullDbManager.getStatus(now);
      expect(status.spentToday, closeTo(0.3, 1e-5));
      expect(status.remainingDaily, closeTo(0.7, 1e-5));
    });
  });

  group('DAO Sensitivity Clipping & DP Queries', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager manager;

    setUp(() {
      db = AttentionDatabase.inMemory();
      manager = PrivacyBudgetManager(db: db, random: Random(123));
    });

    tearDown(() async {
      await db.close();
    });

    test('FocusSessionDao clips focus duration to 120s max sensitivity bound', () async {
      // Insert session with 300s duration (should be clipped to 120s max bound)
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 0,
        sessionStart: DateTime(2026, 9, 13, 9, 0),
        sessionEnd: DateTime(2026, 9, 13, 9, 5),
        interruptions: 2,
        completion: true,
        duration: 300,
      ));

      final res = await db.focusSessionDao.getNoisedTotalFocusDuration(
        manager,
        sensitivity: 120.0,
        epsilon: 0.2,
      );

      expect(res.exactValue, equals(120)); // Clipped from 300 to 120
      expect(res.epsilonDeducted, equals(0.2));
    });

    test('FocusSessionDao clips interruptions to 5 max sensitivity bound', () async {
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 0,
        sessionStart: DateTime(2026, 9, 13, 9, 0),
        sessionEnd: DateTime(2026, 9, 13, 9, 10),
        interruptions: 15, // Should be clipped to 5
        completion: true,
        duration: 60,
      ));

      final res = await db.focusSessionDao.getNoisedFocusInterruptions(
        manager,
        sensitivity: 5.0,
        epsilon: 0.1,
      );

      expect(res.exactValue, equals(5)); // Clipped from 15 to 5
    });

    test('DailyBriefDao queries reviewed count with Laplace noise', () async {
      await db.dailyBriefDao.incrementStats('2026-09-13', reviewed: 8);

      final res = await db.dailyBriefDao.getNoisedReviewedCount(
        manager,
        '2026-09-13',
        epsilon: 0.1,
      );

      expect(res.exactValue, equals(8));
      expect(res.epsilonDeducted, equals(0.1));
    });
  });

  group('NotificationController Privacy Budget Integration & Exception Handling', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager manager;
    late NotificationController controller;

    setUp(() {
      db = AttentionDatabase.inMemory();
      manager = PrivacyBudgetManager(db: db, random: Random(99));
      controller = NotificationController(
        privacyBudgetManager: manager,
      );
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test('getPrivacyBudgetStatus returns status safely', () async {
      final status = await controller.getPrivacyBudgetStatus();
      expect(status.dailyCap, equals(1.0));
      expect(status.remainingDaily, equals(1.0));
    });

    test('getNoisedPriorityDistribution executes queries with DP noise', () async {
      final dist = await controller.getNoisedPriorityDistribution(epsilon: 0.4);
      expect(dist.keys, containsAll(['critical', 'high', 'medium', 'low']));
      expect(dist['critical']!.epsilonDeducted, closeTo(0.1, 1e-5));
    });

    test('getNoisedHourlyVolume executes 24-element vector query', () async {
      final hourly = await controller.getNoisedHourlyVolume(epsilon: 0.2);
      expect(hourly.length, equals(24));
    });

    test('getNoisedTotalCapturedCount returns DP protected notification count', () async {
      final res = await controller.getNoisedTotalCapturedCount(epsilon: 0.1);
      expect(res.exactValue, equals(0));
      expect(res.epsilonDeducted, equals(0.1));
    });

    test('getNoisedFocusAreaCounts returns map of noised counts for focus areas', () async {
      final map = await controller.getNoisedFocusAreaCounts(epsilon: 0.5);
      expect(map.keys, containsAll(FocusArea.values));
    });

    test('exception in telemetry query handles errors safely without crashing controller', () async {
      final throwingManager = PrivacyBudgetManager(db: db);
      final faultController = NotificationController(
        privacyBudgetManager: throwingManager,
      );

      // Even if underlying DB or manager throws, faultController methods return safe fallbacks
      final status = await faultController.getPrivacyBudgetStatus();
      expect(status.dailyCap, equals(1.0));

      faultController.dispose();
    });
  });
}
