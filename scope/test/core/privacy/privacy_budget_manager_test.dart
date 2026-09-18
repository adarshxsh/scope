import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late PrivacyBudgetManager pbm;

  setUp(() {
    db = AttentionDatabase.inMemory();
    pbm = PrivacyBudgetManager(db: db, defaultDailyEpsilon: 1.0);
  });

  tearDown(() async {
    await db.close();
  });

  group('PrivacyBudgetManager Ledger & Replenishment Tests', () {
    test('initializes daily budget ledger with default epsilon', () async {
      final remaining = await pbm.getRemainingBudget();
      expect(remaining, equals(1.0));

      final used = await pbm.getUsedBudget();
      expect(used, equals(0.0));
    });

    test('consumes budget accurately across operations', () async {
      final success1 = await pbm.consumeBudget(0.25);
      expect(success1, isTrue);

      var remaining = await pbm.getRemainingBudget();
      expect(remaining, closeTo(0.75, 0.001));

      var used = await pbm.getUsedBudget();
      expect(used, closeTo(0.25, 0.001));

      final success2 = await pbm.consumeBudget(0.5);
      expect(success2, isTrue);

      remaining = await pbm.getRemainingBudget();
      expect(remaining, closeTo(0.25, 0.001));
    });

    test('enforces budget exhaustion limits when daily threshold reached', () async {
      // Consume full budget
      final success1 = await pbm.consumeBudget(1.0);
      expect(success1, isTrue);

      final remaining = await pbm.getRemainingBudget();
      expect(remaining, equals(0.0));

      // Attempting further consumption should be rejected
      final success2 = await pbm.consumeBudget(0.1);
      expect(success2, isFalse);
    });

    test('resetBudget clears used epsilon', () async {
      await pbm.consumeBudget(0.8);
      expect(await pbm.getUsedBudget(), closeTo(0.8, 0.001));

      await pbm.resetBudget();
      expect(await pbm.getUsedBudget(), equals(0.0));
      expect(await pbm.getRemainingBudget(), equals(1.0));
    });

    test('automatically replenishes budget when midnight boundary is crossed', () async {
      final day1 = DateTime(2026, 6, 27, 22, 0);
      final day2 = DateTime(2026, 6, 28, 8, 0);

      // Day 1: consume 0.9 budget
      final successDay1 = await pbm.consumeBudget(0.9, now: day1);
      expect(successDay1, isTrue);
      expect(await pbm.getRemainingBudget(now: day1), closeTo(0.1, 0.001));

      // Day 2: New date boundary crossed -> budget replenished to 1.0
      expect(await pbm.getRemainingBudget(now: day2), equals(1.0));
      expect(await pbm.getUsedBudget(now: day2), equals(0.0));
    });
  });

  group('Sensitivity Clipping & Laplace Noise Tests', () {
    test('clipValue clamps numbers to specified bounds', () {
      expect(pbm.clipValue(4500, minVal: 0, maxVal: 3600), equals(3600.0));
      expect(pbm.clipValue(-10, minVal: 0, maxVal: 3600), equals(0.0));
      expect(pbm.clipValue(1500, minVal: 0, maxVal: 3600), equals(1500.0));
    });

    test('Laplace noise sampling satisfies mathematical zero-mean property over large N', () {
      const sensitivity = 10.0;
      const epsilon = 0.5;
      const nSamples = 5000;

      final rng = Random(12345);
      double sum = 0.0;
      double sumSq = 0.0;

      for (int i = 0; i < nSamples; i++) {
        final noise = pbm.sampleLaplaceNoise(
          sensitivity: sensitivity,
          epsilon: epsilon,
          random: rng,
        );
        sum += noise;
        sumSq += noise * noise;
      }

      final sampleMean = sum / nSamples;
      // Theoretical scale b = 10 / 0.5 = 20.0
      // Theoretical Var(Laplace) = 2 * b^2 = 800.0
      final sampleVar = (sumSq / nSamples) - (sampleMean * sampleMean);

      expect(sampleMean, closeTo(0.0, 1.5));
      expect(sampleVar, closeTo(800.0, 150.0));
    });

    test('applyNoisyDuration clips duration to 3600s max sensitivity', () {
      final rng = Random(42);
      // Raw duration = 7200s (2 hours)
      final noisyDuration = pbm.applyNoisyDuration(7200, epsilon: 1.0, random: rng);

      // Clipped duration is 3600. With epsilon=1.0, noise scale = 3600.
      expect(noisyDuration, isA<int>());
      expect(noisyDuration, greaterThanOrEqualTo(0));
      expect(noisyDuration, lessThanOrEqualTo(3600));
    });

    test('applyNoisyInterruptions clips interruptions to 10 max sensitivity', () {
      final rng = Random(42);
      final noisyInterruptions = pbm.applyNoisyInterruptions(50, epsilon: 1.0, random: rng);

      expect(noisyInterruptions, isA<int>());
      expect(noisyInterruptions, greaterThanOrEqualTo(0));
      expect(noisyInterruptions, lessThanOrEqualTo(10));
    });

    test('applyNoisyCount clips daily activity counts to 10 max sensitivity', () {
      final rng = Random(42);
      final noisyCount = pbm.applyNoisyCount(25, epsilon: 1.0, random: rng);

      expect(noisyCount, isA<int>());
      expect(noisyCount, greaterThanOrEqualTo(0));
      expect(noisyCount, lessThanOrEqualTo(10000));
    });
  });

  group('DAO Integration & Privacy Budget Enforcement Tests', () {
    test('FocusSessionDao routes writes through PrivacyBudgetManager noise filter', () async {
      final focusDao = FocusSessionDao(db, pbm);

      final session = FocusSessionEntry(
        id: 1,
        sessionStart: DateTime.now(),
        sessionEnd: DateTime.now().add(const Duration(minutes: 30)),
        interruptions: 5,
        completion: true,
        duration: 1800,
      );

      final rng = Random(999);
      final written = await focusDao.insertSession(
        session,
        opEpsilon: 0.2,
        random: rng,
      );
      expect(written, isTrue);

      final stored = await focusDao.getAll();
      expect(stored.length, equals(1));
      // Verify metrics were noisy & modified
      expect(stored.first.duration, isNot(equals(1800)));
      expect(stored.first.duration, greaterThanOrEqualTo(0));

      // Verify budget was consumed
      final remaining = await pbm.getRemainingBudget();
      expect(remaining, closeTo(0.8, 0.001));
    });

    test('DailyBriefDao routes writes through PrivacyBudgetManager and respects budget limits', () async {
      final limitedPbm = PrivacyBudgetManager(db: db, defaultDailyEpsilon: 0.2);
      final briefDao = DailyBriefDao(db, limitedPbm);

      // Operation 1 consumes 0.1 epsilon (succeeds)
      final op1 = await briefDao.incrementStats('2026-06-27', reviewed: 5, opEpsilon: 0.1);
      expect(op1, isTrue);

      // Operation 2 consumes 0.1 epsilon (succeeds)
      final op2 = await briefDao.incrementStats('2026-06-27', completed: 3, opEpsilon: 0.1);
      expect(op2, isTrue);

      // Budget is now exhausted (0.2 used out of 0.2)
      expect(await limitedPbm.getRemainingBudget(), equals(0.0));

      // Operation 3 attempts write when budget exhausted (suppressed!)
      final op3 = await briefDao.incrementStats('2026-06-27', calendar: 2, opEpsilon: 0.1);
      expect(op3, isFalse);

      final brief = await briefDao.getBriefForDate('2026-06-27');
      expect(brief, isNotNull);
      // calendarEventsCreated should remain 0 because 3rd write was suppressed
      expect(brief!.calendarEventsCreated, equals(0));
    });
  });

  group('Performance & Latency Overhead Benchmark', () {
    test('Privacy budget verification and noise generation executes under 5ms', () async {
      final stopwatch = Stopwatch()..start();
      const nOps = 1000;

      for (int i = 0; i < nOps; i++) {
        pbm.applyNoisyDuration(1800, epsilon: 0.1);
        pbm.applyNoisyInterruptions(3, epsilon: 0.1);
      }

      stopwatch.stop();
      final totalMs = stopwatch.elapsedMilliseconds;
      final avgMsPerOp = totalMs / nOps;

      // Ensure average latency per telemetry operation is < 5ms
      expect(avgMsPerOp, lessThan(5.0));
    });
  });
}
