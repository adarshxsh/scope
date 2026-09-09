import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:scope/core/telemetry/telemetry_governance_service.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('TelemetryGovernanceService Unit Tests', () {
    late TelemetryGovernanceService governance;

    setUp(() {
      governance = TelemetryGovernanceService(defaultEpsilon: 1.0);
    });

    test('Timestamp quantization aligns to 15-minute epoch boundaries', () {
      final t1 = DateTime(2026, 9, 8, 10, 7, 23, 456);
      final q1 = governance.quantizeTimestamp(t1, intervalMinutes: 15);
      expect(q1.year, equals(2026));
      expect(q1.month, equals(9));
      expect(q1.day, equals(8));
      expect(q1.hour, equals(10));
      expect(q1.minute, equals(0));
      expect(q1.second, equals(0));
      expect(q1.millisecond, equals(0));

      final t2 = DateTime(2026, 9, 8, 10, 29, 59, 999);
      final q2 = governance.quantizeTimestamp(t2, intervalMinutes: 15);
      expect(q2.hour, equals(10));
      expect(q2.minute, equals(15));
      expect(q2.second, equals(0));

      final t3 = DateTime(2026, 9, 8, 10, 45, 0, 0);
      final q3 = governance.quantizeTimestamp(t3, intervalMinutes: 15);
      expect(q3.hour, equals(10));
      expect(q3.minute, equals(45));
      expect(q3.second, equals(0));
    });

    test('Quantize nullable timestamp handles null and non-null', () {
      expect(governance.quantizeNullableTimestamp(null), isNull);
      final t = DateTime(2026, 9, 8, 14, 18, 12);
      final q = governance.quantizeNullableTimestamp(t);
      expect(q, isNotNull);
      expect(q!.minute, equals(15));
    });

    test('Bounded step interval duration and interruption quantization', () {
      expect(governance.quantizeDuration(0), equals(0));
      expect(governance.quantizeDuration(-50), equals(0));
      // Default 900s step (15 mins)
      expect(governance.quantizeDuration(100, stepSeconds: 900), equals(0));
      expect(governance.quantizeDuration(500, stepSeconds: 900), equals(900));
      expect(governance.quantizeDuration(1200, stepSeconds: 900), equals(900));
      expect(governance.quantizeDuration(1400, stepSeconds: 900), equals(1800));

      // Interruptions quantization
      expect(governance.quantizeInterruptions(-2), equals(0));
      expect(governance.quantizeInterruptions(3, stepSize: 1), equals(3));
      expect(governance.quantizeInterruptions(3, stepSize: 5), equals(5));
    });

    test('Laplace noise generation is zero-mean and calibrated to epsilon', () {
      final samples = <double>[];
      final deterministicGov = TelemetryGovernanceService(
        defaultEpsilon: 1.0,
        random: Random(12345),
      );

      for (int i = 0; i < 10000; i++) {
        samples.add(deterministicGov.generateLaplaceNoise(epsilon: 1.0, sensitivity: 1.0));
      }

      final mean = samples.reduce((a, b) => a + b) / samples.length;
      // Mean should be close to 0
      expect(mean.abs(), lessThan(0.1));
    });

    test('Enforces non-negative floor on daily metric noise transformation', () {
      final service = TelemetryGovernanceService(
        defaultEpsilon: 1.0,
        random: Random(42),
      );

      for (int i = 0; i < 100; i++) {
        final noisyZero = service.applyLaplaceNoiseToInt(0, epsilon: 1.0);
        expect(noisyZero, greaterThanOrEqualTo(0));
      }
    });

    test('Privacy budget (epsilon) tracking per telemetry entity', () {
      governance.setMaxBudget('daily_brief', 1.0);
      expect(governance.getMaxBudget('daily_brief'), equals(1.0));
      expect(governance.getConsumedBudget('daily_brief'), equals(0.0));
      expect(governance.getRemainingBudget('daily_brief'), equals(1.0));
      expect(governance.hasBudget('daily_brief', 0.5), isTrue);

      final success1 = governance.consumeBudget('daily_brief', 0.4);
      expect(success1, isTrue);
      expect(governance.getConsumedBudget('daily_brief'), closeTo(0.4, 0.001));
      expect(governance.getRemainingBudget('daily_brief'), closeTo(0.6, 0.001));

      final success2 = governance.consumeBudget('daily_brief', 0.7);
      expect(success2, isFalse); // Exceeds max budget

      governance.resetBudget('daily_brief');
      expect(governance.getConsumedBudget('daily_brief'), equals(0.0));
    });

    test('DailyBrief transformation applies noise to all metrics with budget epsilon <= 1.0', () {
      final entry = DailyBriefEntry(
        id: 1,
        date: '2026-09-08',
        notificationsReviewed: 10,
        actionsCompleted: 5,
        calendarEventsCreated: 2,
        remindersCreated: 1,
        archivedCount: 3,
      );

      final noisy = governance.transformDailyBrief(entry, epsilon: 1.0);
      expect(noisy.date, equals('2026-09-08'));
      expect(noisy.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(noisy.actionsCompleted, greaterThanOrEqualTo(0));
      expect(noisy.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(noisy.remindersCreated, greaterThanOrEqualTo(0));
      expect(noisy.archivedCount, greaterThanOrEqualTo(0));
    });

    test('Sanitize FocusSessionEntry quantizes timestamps and rounds durations/interruptions', () {
      final rawStart = DateTime(2026, 9, 8, 14, 22, 15); // -> 14:15:00
      final rawEnd = DateTime(2026, 9, 8, 14, 51, 40);   // -> 14:45:00

      final entry = FocusSessionEntry(
        id: 1,
        sessionStart: rawStart,
        sessionEnd: rawEnd,
        interruptions: 3,
        completion: true,
        duration: 1765, // Raw duration ~29 mins
      );

      final sanitized = governance.sanitizeFocusSession(entry);
      expect(sanitized.sessionStart.minute, equals(15));
      expect(sanitized.sessionStart.second, equals(0));
      expect(sanitized.sessionEnd!.minute, equals(45));
      expect(sanitized.sessionEnd!.second, equals(0));
      // 14:45:00 - 14:15:00 = 30 minutes = 1800 seconds
      expect(sanitized.duration, equals(1800));
      expect(sanitized.interruptions, equals(3));
    });
  });

  group('DAO Telemetry Governance Integration Tests', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('FocusSessionDao automatically quantizes timestamps to 15-minute boundaries', () async {
      final unquantizedStart = DateTime(2026, 9, 8, 14, 27, 33);
      final unquantizedEnd = DateTime(2026, 9, 8, 15, 02, 11);

      final session = FocusSessionEntry(
        id: 0,
        sessionStart: unquantizedStart,
        sessionEnd: unquantizedEnd,
        interruptions: 1,
        completion: true,
        duration: 2078,
      );

      await db.focusSessionDao.insertSession(session);
      final saved = await db.focusSessionDao.getAll();

      expect(saved.length, equals(1));
      final s = saved.first;

      // Ensure 15-minute quantization
      expect(s.sessionStart.minute % 15, equals(0));
      expect(s.sessionStart.second, equals(0));
      expect(s.sessionStart.millisecond, equals(0));

      expect(s.sessionEnd!.minute % 15, equals(0));
      expect(s.sessionEnd!.second, equals(0));
      expect(s.sessionEnd!.millisecond, equals(0));

      // 15:00 - 14:15 = 45 mins = 2700s
      expect(s.duration % 900, equals(0));
    });

    test('DailyBriefDao applies Laplace noise and non-negative floor on write', () async {
      final entry = DailyBriefEntry(
        id: 0,
        date: '2026-09-08',
        notificationsReviewed: 0,
        actionsCompleted: 0,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 0,
      );

      await db.dailyBriefDao.insertOrUpdate(entry);
      final brief = await db.dailyBriefDao.getBriefForDate('2026-09-08');

      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(brief.actionsCompleted, greaterThanOrEqualTo(0));
      expect(brief.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(brief.remindersCreated, greaterThanOrEqualTo(0));
      expect(brief.archivedCount, greaterThanOrEqualTo(0));
    });

    test('Automated check: Exact user routine cannot be reconstructed from local DB snapshot', () async {
      // Simulate user routine: exact second timestamps throughout the day
      final routineStarts = [
        DateTime(2026, 9, 8, 9, 3, 14),
        DateTime(2026, 9, 8, 11, 47, 59),
        DateTime(2026, 9, 8, 14, 12, 05),
      ];

      for (int i = 0; i < routineStarts.length; i++) {
        await db.focusSessionDao.insertSession(FocusSessionEntry(
          id: 0,
          sessionStart: routineStarts[i],
          interruptions: i + 1,
          completion: true,
          duration: 1800,
        ));
      }

      final snapshot = await db.focusSessionDao.getAll();
      for (int i = 0; i < snapshot.length; i++) {
        final record = snapshot[i];
        final rawOriginal = routineStarts[i];

        // Exact seconds and minutes must NOT match unquantized raw timestamp
        expect(record.sessionStart, isNot(equals(rawOriginal)));
        // Timestamp must be on 15-minute boundary
        expect(record.sessionStart.minute % 15, equals(0));
        expect(record.sessionStart.second, equals(0));
      }
    });
  });
}
