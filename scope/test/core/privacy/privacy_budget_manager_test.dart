import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('LaplaceNoise Unit Tests', () {
    test('sample generates values around 0', () {
      final rng = Random(42);
      final samples = List.generate(1000, (_) => LaplaceNoise.sample(1.0, random: rng));
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      expect(mean.abs(), lessThan(0.2));
    });

    test('scaleFromSensitivity calculates delta_f / epsilon correctly', () {
      expect(LaplaceNoise.scaleFromSensitivity(1.0, 0.5), equals(2.0));
      expect(LaplaceNoise.scaleFromSensitivity(2.0, 1.0), equals(2.0));
      expect(() => LaplaceNoise.scaleFromSensitivity(1.0, 0.0), throwsArgumentError);
    });
  });

  group('PrivacyBudgetManager Unit Tests (In-Memory Fallback)', () {
    test('Budget tracking and deduction without database', () async {
      final pbm = PrivacyBudgetManager(
        dailyEpsilonCap: 1.0,
        monthlyEpsilonCap: 10.0,
        defaultEpsilonPerQuery: 0.2,
      );

      final now = DateTime(2026, 9, 16);
      var status = await pbm.getStatus(now);
      expect(status.spentToday, equals(0.0));
      expect(status.remainingDaily, equals(1.0));
      expect(status.isExhausted, isFalse);

      final result = await pbm.executeNoisedQuery<int>(
        exactQuery: () async => 42,
        sensitivity: 1.0,
        epsilon: 0.2,
        now: now,
      );

      expect(result.exactValue, equals(42));
      expect(result.epsilonDeducted, equals(0.2));
      expect(result.isBudgetExhausted, isFalse);

      status = await pbm.getStatus(now);
      expect(status.spentToday, closeTo(0.2, 0.001));
      expect(status.remainingDaily, closeTo(0.8, 0.001));
    });

    test('Graceful coarsening when budget is exhausted', () async {
      final pbm = PrivacyBudgetManager(
        dailyEpsilonCap: 0.3,
        monthlyEpsilonCap: 10.0,
        defaultEpsilonPerQuery: 0.2,
      );

      final now = DateTime(2026, 9, 16);

      // Query 1 consumes 0.2
      await pbm.executeNoisedQuery<int>(
        exactQuery: () async => 50,
        sensitivity: 1.0,
        epsilon: 0.2,
        now: now,
      );

      // Query 2 requests 0.2, exceeding daily budget of 0.3
      final result2 = await pbm.executeNoisedQuery<int>(
        exactQuery: () async => 57,
        sensitivity: 1.0,
        epsilon: 0.2,
        coarseningBucket: 10.0,
        now: now,
      );

      expect(result2.isBudgetExhausted, isTrue);
      expect(result2.epsilonDeducted, equals(0.0));
      expect(result2.coarsenedBounds, equals('[50 - 60]'));
      expect(result2.noisedValue, equals(55.0));
    });
  });

  group('PrivacyBudgetManager Database Persistent Tests', () {
    late AttentionDatabase db;
    late PrivacyBudgetManager pbm;

    setUp(() {
      db = AttentionDatabase.inMemory();
      pbm = PrivacyBudgetManager(
        db: db,
        dailyEpsilonCap: 1.0,
        monthlyEpsilonCap: 10.0,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Records query consumption into persistent database ledger', () async {
      final now = DateTime(2026, 9, 16);

      await pbm.executeNoisedQuery<int>(
        exactQuery: () async => 100,
        sensitivity: 1.0,
        epsilon: 0.4,
        now: now,
      );

      final status = await pbm.getStatus(now);
      expect(status.spentToday, closeTo(0.4, 0.001));

      final spentInDb = await db.privacyLedgerDao.getEpsilonSpentForDate('2026-09-16');
      expect(spentInDb, closeTo(0.4, 0.001));
    });

    test('Records remote cross-device consumption to maintain fleet-wide privacy budget', () async {
      final now = DateTime(2026, 9, 16);

      await pbm.recordRemoteConsumption(
        date: '2026-09-16',
        epsilon: 0.5,
      );

      final status = await pbm.getStatus(now);
      expect(status.spentToday, closeTo(0.5, 0.001));
      expect(status.remainingDaily, closeTo(0.5, 0.001));
    });
  });
}
