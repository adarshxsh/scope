import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/telemetry_governance_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late TelemetryGovernanceService service;

  setUp(() {
    db = AttentionDatabase.inMemory();
    service = TelemetryGovernanceService(db, math.Random(42));
  });

  tearDown(() async {
    await db.close();
  });

  group('TelemetryGovernanceService Timestamp Quantization', () {
    test('quantizes timestamps to 15-minute boundaries', () {
      final dt1 = DateTime(2026, 9, 12, 10, 7, 0);
      final q1 = service.quantizeTimestamp(dt1);
      expect(q1, DateTime(2026, 9, 12, 10, 0, 0));
      expect(q1.minute % 15, equals(0));
      expect(q1.second, equals(0));

      final dt2 = DateTime(2026, 9, 12, 10, 7, 31);
      final q2 = service.quantizeTimestamp(dt2);
      expect(q2, DateTime(2026, 9, 12, 10, 15, 0));
      expect(q2.minute % 15, equals(0));

      final dt3 = DateTime(2026, 9, 12, 10, 53, 0);
      final q3 = service.quantizeTimestamp(dt3);
      expect(q3, DateTime(2026, 9, 12, 11, 0, 0));
      expect(q3.minute % 15, equals(0));
    });
  });

  group('TelemetryGovernanceService Duration & Interruption Quantization', () {
    test('quantizes duration into 5-minute (300-second) blocks', () {
      expect(service.quantizeDuration(0), equals(0));
      expect(service.quantizeDuration(120), equals(0)); // 2 min -> 0
      expect(service.quantizeDuration(200), equals(300)); // 3.33 min -> 5 min (300s)
      expect(service.quantizeDuration(600), equals(600)); // 10 min -> 10 min
      expect(service.quantizeDuration(800), equals(900)); // 13.3 min -> 15 min (900s)
      expect(service.quantizeDuration(-50), equals(0));
    });

    test('quantizes interruptions', () {
      expect(service.quantizeInterruptions(0), equals(0));
      expect(service.quantizeInterruptions(3), equals(3));
      expect(service.quantizeInterruptions(-2), equals(0));
    });
  });

  group('TelemetryGovernanceService Laplace Noise Injection', () {
    test('injects noise into count and clamps to non-negative', () {
      for (int i = 0; i < 100; i++) {
        final noisy = service.injectLaplaceNoiseToCount(10);
        expect(noisy, greaterThanOrEqualTo(0));
      }
    });

    test('preserves statistical utility with low average relative error on aggregates', () {
      const rawCount = 100;
      int totalNoisy = 0;
      const samples = 200;

      for (int i = 0; i < samples; i++) {
        totalNoisy += service.injectLaplaceNoiseToCount(rawCount);
      }

      final averageNoisy = totalNoisy / samples;
      final relativeVariance = (averageNoisy - rawCount).abs() / rawCount;

      // Relative error on aggregate mean is well under 5%
      expect(relativeVariance, lessThan(0.05));
    });
  });

  group('TelemetryGovernanceService Privacy Budget Enforcement', () {
    test('enforces daily privacy budget cap (\u03b5 = 1.0)', () {
      const testDate = '2026-09-12';
      expect(service.canSpendBudget(0.5, date: testDate), isTrue);

      service.consumeBudget(0.5, date: testDate);
      expect(service.consumedBudgetToday, closeTo(0.5, 1e-5));
      expect(service.remainingBudgetToday, closeTo(0.5, 1e-5));

      service.consumeBudget(0.5, date: testDate);
      expect(service.consumedBudgetToday, closeTo(1.0, 1e-5));
      expect(service.remainingBudgetToday, equals(0.0));

      expect(service.canSpendBudget(0.1, date: testDate), isFalse);
      expect(
        () => service.consumeBudget(0.1, date: testDate),
        throwsA(isA<PrivacyBudgetExceededException>()),
      );
    });

    test('resets privacy budget when date changes', () {
      service.consumeBudget(1.0, date: '2026-09-12');
      expect(service.remainingBudgetToday, equals(0.0));

      // New date resets budget
      expect(service.canSpendBudget(0.5, date: '2026-09-13'), isTrue);
      expect(service.remainingBudgetToday, equals(1.0));
    });
  });

  group('TelemetryGovernanceService Database Persistence Interception', () {
    test('persists quantized focus session timestamps to SQLite', () async {
      final startTime = DateTime(2026, 9, 12, 14, 7, 12); // Quantizes to 14:00
      final sessionId = await service.startFocusSession(startTime);

      final active = await db.focusSessionDao.getActiveSession();
      expect(active, isNotNull);
      expect(active!.id, equals(sessionId));
      expect(active.sessionStart, equals(DateTime(2026, 9, 12, 14, 0, 0)));

      final endTime = DateTime(2026, 9, 12, 14, 28, 45); // Quantizes to 14:30
      await service.finishFocusSession(
        activeSession: active,
        endTime: endTime,
        interruptions: 2,
      );

      final allSessions = await db.focusSessionDao.getAll();
      expect(allSessions.length, equals(1));
      final updated = allSessions.first;

      expect(updated.sessionStart, equals(DateTime(2026, 9, 12, 14, 0, 0)));
      expect(updated.sessionEnd, equals(DateTime(2026, 9, 12, 14, 30, 0)));
      expect(updated.sessionStart.minute % 15, equals(0));
      expect(updated.sessionEnd!.minute % 15, equals(0));
      expect(updated.duration, equals(1800)); // Quantized 14:00 to 14:30 = 30 min (1800s)
      expect(updated.interruptions, equals(2));
      expect(updated.completion, isTrue);
    });

    test('persists noise-injected daily brief metrics to SQLite', () async {
      const date = '2026-09-12';
      await service.recordDailyBriefMetrics(
        date,
        reviewed: 10,
        completed: 5,
        calendar: 2,
        reminders: 1,
        archived: 3,
        epsilonCost: 0.5,
      );

      final brief = await service.getDailyBrief(date);
      expect(brief, isNotNull);
      expect(brief!.date, equals(date));
      expect(brief.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(brief.actionsCompleted, greaterThanOrEqualTo(0));
      expect(brief.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(brief.remindersCreated, greaterThanOrEqualTo(0));
      expect(brief.archivedCount, greaterThanOrEqualTo(0));
    });
  });

  group('NotificationController Integration', () {
    test('routes focus sessions and metrics through TelemetryGovernanceService', () async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      final controller = NotificationController(
        telemetryService: service,
        container: container,
      );

      controller.startFocusSession();
      expect(controller.inFocusSession, isTrue);

      final active = await db.focusSessionDao.getActiveSession();
      expect(active, isNotNull);
      expect(active!.sessionStart.minute % 15, equals(0));

      controller.recordReviewed();
      controller.recordAction();

      controller.finishFocusSession();
      expect(controller.inFocusSession, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final allSessions = await db.focusSessionDao.getAll();
      expect(allSessions.length, equals(1));
      expect(allSessions.first.sessionEnd, isNotNull);
      expect(allSessions.first.sessionEnd!.minute % 15, equals(0));
    });
  });
}
