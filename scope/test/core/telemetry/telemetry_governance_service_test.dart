import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/telemetry/telemetry_governance_service.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('TelemetryGovernanceService Tests', () {
    setUp(() {
      TelemetryGovernanceService.resetPrivacyBudget();
    });

    test('quantizeTimestamp quantizes DateTime to 15-minute epoch boundary', () {
      final time1 = DateTime.utc(2026, 9, 18, 10, 14, 59);
      final quantized1 = TelemetryGovernanceService.quantizeTimestamp(time1);
      expect(quantized1, DateTime.utc(2026, 9, 18, 10, 0, 0));

      final time2 = DateTime.utc(2026, 9, 18, 10, 15, 01);
      final quantized2 = TelemetryGovernanceService.quantizeTimestamp(time2);
      expect(quantized2, DateTime.utc(2026, 9, 18, 10, 15, 0));

      final time3 = DateTime.utc(2026, 9, 18, 10, 29, 59);
      final quantized3 = TelemetryGovernanceService.quantizeTimestamp(time3);
      expect(quantized3, DateTime.utc(2026, 9, 18, 10, 15, 0));
    });

    test('quantizeTimestampMs handles millisecond values and edge cases', () {
      const fifteenMinsMs = 15 * 60 * 1000;
      final ms = DateTime.utc(2026, 9, 18, 10, 22, 10).millisecondsSinceEpoch;
      final quantizedMs = TelemetryGovernanceService.quantizeTimestampMs(ms);

      expect(quantizedMs % fifteenMinsMs, 0);
      expect(TelemetryGovernanceService.quantizeTimestampMs(0), 0);
      expect(TelemetryGovernanceService.quantizeTimestampMs(-500), 0);
    });

    test('quantizeDuration buckets session duration in seconds', () {
      expect(TelemetryGovernanceService.quantizeDuration(250), 0); // < 300
      expect(TelemetryGovernanceService.quantizeDuration(300), 300);
      expect(TelemetryGovernanceService.quantizeDuration(599), 300);
      expect(TelemetryGovernanceService.quantizeDuration(600), 600);
      expect(TelemetryGovernanceService.quantizeDuration(-50), 0);
    });

    test('quantizeInterruptions caps interruption counts', () {
      expect(TelemetryGovernanceService.quantizeInterruptions(3), 3);
      expect(TelemetryGovernanceService.quantizeInterruptions(15, maxCap: 10), 10);
      expect(TelemetryGovernanceService.quantizeInterruptions(-2), 0);
    });

    test('addLaplaceNoise injects noise and clamps results to non-negative', () {
      final rand = math.Random(42);
      final noisy1 = TelemetryGovernanceService.addLaplaceNoise(
        10,
        sensitivity: 1.0,
        epsilon: 1.0,
        random: rand,
      );
      expect(noisy1, isA<int>());
      expect(noisy1 >= 0, isTrue);

      final noisyZero = TelemetryGovernanceService.addLaplaceNoise(
        0,
        sensitivity: 1.0,
        epsilon: 0.1,
        random: math.Random(123),
      );
      expect(noisyZero >= 0, isTrue);
    });

    test('Privacy budget tracking enforces max budget limits', () {
      TelemetryGovernanceService.resetPrivacyBudget();
      expect(TelemetryGovernanceService.spentPrivacyBudgetEpsilon, 0.0);
      expect(TelemetryGovernanceService.remainingPrivacyBudgetEpsilon, 2.0);

      expect(TelemetryGovernanceService.tryConsumeBudget(1.0), isTrue);
      expect(TelemetryGovernanceService.spentPrivacyBudgetEpsilon, 1.0);
      expect(TelemetryGovernanceService.remainingPrivacyBudgetEpsilon, 1.0);

      expect(TelemetryGovernanceService.tryConsumeBudget(1.0), isTrue);
      expect(TelemetryGovernanceService.spentPrivacyBudgetEpsilon, 2.0);
      expect(TelemetryGovernanceService.remainingPrivacyBudgetEpsilon, 0.0);

      // Exceeding budget returns false
      expect(TelemetryGovernanceService.tryConsumeBudget(0.5), isFalse);

      TelemetryGovernanceService.resetPrivacyBudget();
      expect(TelemetryGovernanceService.spentPrivacyBudgetEpsilon, 0.0);
    });

    test('sanitizeFocusSession quantizes session start, end, duration, and interruptions', () {
      final session = FocusSessionEntry(
        id: 1,
        sessionStart: DateTime.utc(2026, 9, 18, 14, 23, 45),
        sessionEnd: DateTime.utc(2026, 9, 18, 14, 48, 12),
        duration: 1467, // ~24 mins
        interruptions: 12,
        completion: true,
      );

      final sanitized = TelemetryGovernanceService.sanitizeFocusSession(session);

      expect(sanitized.id, 1);
      expect(sanitized.sessionStart, DateTime.utc(2026, 9, 18, 14, 15, 0));
      expect(sanitized.sessionEnd, DateTime.utc(2026, 9, 18, 14, 45, 0));
      expect(sanitized.duration, 1200); // 1467 ~/ 300 * 300 = 1200
      expect(sanitized.interruptions, 10); // capped at 10
      expect(sanitized.completion, isTrue);
    });

    test('sanitizeDailyBrief injects noise and preserves entry identity', () {
      final brief = DailyBriefEntry(
        id: 5,
        date: '2026-09-18',
        notificationsReviewed: 20,
        actionsCompleted: 10,
        calendarEventsCreated: 3,
        remindersCreated: 4,
        archivedCount: 15,
      );

      final sanitized = TelemetryGovernanceService.sanitizeDailyBrief(
        brief,
        epsilon: 1.0,
        random: math.Random(100),
      );

      expect(sanitized.id, 5);
      expect(sanitized.date, '2026-09-18');
      expect(sanitized.notificationsReviewed >= 0, isTrue);
      expect(sanitized.actionsCompleted >= 0, isTrue);
      expect(sanitized.calendarEventsCreated >= 0, isTrue);
      expect(sanitized.remindersCreated >= 0, isTrue);
      expect(sanitized.archivedCount >= 0, isTrue);
    });

    test('getAuditMetrics returns system state audit parameters', () {
      final metrics = TelemetryGovernanceService.getAuditMetrics();
      expect(metrics.containsKey('total_sanitized_sessions'), isTrue);
      expect(metrics.containsKey('total_sanitized_briefs'), isTrue);
      expect(metrics.containsKey('spent_privacy_budget_epsilon'), isTrue);
      expect(metrics.containsKey('max_privacy_budget_epsilon'), isTrue);
      expect(metrics['epoch_interval_minutes'], 15);
    });
  });

  group('DAO Telemetry Sanitization Integration Tests', () {
    late AttentionDatabase db;

    setUp(() {
      TelemetryGovernanceService.resetPrivacyBudget();
      db = AttentionDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('FocusSessionDao automatically sanitizes sessions prior to database write', () async {
      final session = FocusSessionEntry(
        id: 0,
        sessionStart: DateTime.utc(2026, 9, 18, 11, 14, 10),
        sessionEnd: DateTime.utc(2026, 9, 18, 11, 28, 55),
        duration: 885,
        interruptions: 14,
        completion: true,
      );

      await db.focusSessionDao.insertSession(session);
      final retrieved = await db.focusSessionDao.getAll();

      expect(retrieved.length, 1);
      final stored = retrieved.first;
      expect(stored.sessionStart.toUtc(), DateTime.utc(2026, 9, 18, 11, 0, 0));
      expect(stored.sessionEnd?.toUtc(), DateTime.utc(2026, 9, 18, 11, 15, 0));
      expect(stored.duration, 600); // 885 ~/ 300 * 300
      expect(stored.interruptions, 10); // Capped at 10
    });

    test('DailyBriefDao provides sanitized daily brief stats on getSanitizedBriefForDate', () async {
      await db.dailyBriefDao.incrementStats(
        '2026-09-18',
        reviewed: 10,
        completed: 5,
        calendar: 2,
        reminders: 1,
        archived: 3,
      );

      final brief = await db.dailyBriefDao.getSanitizedBriefForDate('2026-09-18');
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed >= 0, isTrue);
      expect(brief.actionsCompleted >= 0, isTrue);
      expect(brief.calendarEventsCreated >= 0, isTrue);
      expect(brief.remindersCreated >= 0, isTrue);
      expect(brief.archivedCount >= 0, isTrue);
    });
  });
}
