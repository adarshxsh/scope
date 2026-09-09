import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/telemetry/telemetry_governance_service.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late TelemetryGovernanceService service;

  setUp(() {
    db = AttentionDatabase.inMemory();
    service = TelemetryGovernanceService(db: db, epsilon: 1.0, sensitivity: 1.0);
  });

  tearDown(() async {
    await db.close();
  });

  group('TelemetryGovernanceService - Laplace Noise Parameters', () {
    test('noise generation conforms to configured Laplace scale parameter (scale = 1.0)', () {
      final service1 = TelemetryGovernanceService(db: db, epsilon: 1.0, sensitivity: 1.0);
      expect(service1.scale, equals(1.0));

      const samples = 10000;
      double sum = 0.0;
      double absSum = 0.0;

      for (int i = 0; i < samples; i++) {
        final noise = service1.sampleLaplaceNoise();
        sum += noise;
        absSum += noise.abs();
      }

      final mean = sum / samples;
      final mae = absSum / samples;

      // Mean of Lap(1.0) is 0
      expect(mean.abs(), lessThan(0.1));
      // Mean absolute deviation of Lap(1.0) is 1.0
      expect(mae, greaterThan(0.85));
      expect(mae, lessThan(1.15));
    });

    test('noise generation conforms to configured Laplace scale parameter (scale = 2.0)', () {
      final service2 = TelemetryGovernanceService(db: db, epsilon: 0.5, sensitivity: 1.0);
      expect(service2.scale, equals(2.0));

      const samples = 10000;
      double sum = 0.0;
      double absSum = 0.0;

      for (int i = 0; i < samples; i++) {
        final noise = service2.sampleLaplaceNoise();
        sum += noise;
        absSum += noise.abs();
      }

      final mean = sum / samples;
      final mae = absSum / samples;

      // Mean of Lap(2.0) is 0
      expect(mean.abs(), lessThan(0.15));
      // Mean absolute deviation of Lap(2.0) is 2.0
      expect(mae, greaterThan(1.7));
      expect(mae, lessThan(2.3));
    });

    test('rejects non-positive or oversized epsilon values', () {
      expect(() => TelemetryGovernanceService(db: db, epsilon: 0.0), throwsArgumentError);
      expect(() => TelemetryGovernanceService(db: db, epsilon: -1.0), throwsArgumentError);
      expect(() => TelemetryGovernanceService(db: db, epsilon: 15.0), throwsArgumentError);
    });
  });

  group('TelemetryGovernanceService - Timestamp & Duration Bucketing', () {
    test('quantizes DateTime timestamps into 15-minute discrete buckets', () {
      final t1 = DateTime.utc(2026, 9, 9, 10, 7, 29);
      final q1 = TelemetryGovernanceService.quantizeTimestamp(t1);
      expect(q1.minute, equals(0));
      expect(q1.second, equals(0));
      expect(q1.millisecond, equals(0));

      final t2 = DateTime.utc(2026, 9, 9, 10, 7, 31);
      final q2 = TelemetryGovernanceService.quantizeTimestamp(t2);
      expect(q2.minute, equals(15));
      expect(q2.second, equals(0));

      final t3 = DateTime.utc(2026, 9, 9, 10, 22, 00);
      final q3 = TelemetryGovernanceService.quantizeTimestamp(t3);
      expect(q3.minute, equals(15));

      final t4 = DateTime.utc(2026, 9, 9, 10, 50, 00); // 50m -> rounds to 45m
      final q4 = TelemetryGovernanceService.quantizeTimestamp(t4);
      expect(q4.minute, equals(45));

      final t5 = DateTime.utc(2026, 9, 9, 10, 53, 00); // 53m -> rounds to 11:00 (minute 0)
      final q5 = TelemetryGovernanceService.quantizeTimestamp(t5);
      expect(q5.minute, equals(0));
      expect(q5.hour, equals(11));
    });

    test('session durations under 15 minutes are rounded to nearest interval without dropping sessions', () {
      // 5 minutes (300s) -> rounded to 15 minutes (900s)
      final duration5Min = TelemetryGovernanceService.quantizeDurationSeconds(300);
      expect(duration5Min, equals(900));

      // 1 minute (60s) -> rounded to 15 minutes (900s)
      final duration1Min = TelemetryGovernanceService.quantizeDurationSeconds(60);
      expect(duration1Min, equals(900));

      // 23 minutes (1380s) -> rounded to 23/15 = 1.53 -> 30 minutes (1800s)
      final duration23Min = TelemetryGovernanceService.quantizeDurationSeconds(1380);
      expect(duration23Min, equals(1800));
    });
  });

  group('TelemetryGovernanceService - Telemetry Schema Validation', () {
    test('accepts valid registered events with approved metadata attributes', () {
      final event = TelemetryEvent(
        eventType: 'daily_metrics_update',
        metadata: {
          'date': '2026-09-09',
          'notificationsReviewed': 5,
          'actionsCompleted': 2,
          'calendarEventsCreated': 1,
          'remindersCreated': 0,
          'archivedCount': 1,
        },
      );
      expect(() => service.logEvent(event), returnsNormally);
    });

    test('rejects unregistered event types', () {
      final invalidEvent = TelemetryEvent(
        eventType: 'unregistered_custom_event',
        metadata: {'date': '2026-09-09'},
      );
      expect(() => service.logEvent(invalidEvent), throwsArgumentError);
    });

    test('rejects unapproved metadata attributes', () {
      final invalidMetadataEvent = TelemetryEvent(
        eventType: 'daily_metrics_update',
        metadata: {
          'date': '2026-09-09',
          'unapproved_user_tracker': 'raw_id_123',
        },
      );
      expect(() => service.logEvent(invalidMetadataEvent), throwsArgumentError);
    });
  });

  group('TelemetryGovernanceService - Post-Processing & Persistence', () {
    test('persists focus sessions with 15-minute aligned timestamps', () async {
      final start = DateTime.utc(2026, 9, 9, 10, 4, 0); // rounds to 10:00
      final end = DateTime.utc(2026, 9, 9, 10, 19, 0); // rounds to 10:15

      await service.startFocusSession(start);
      var sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));
      expect(sessions.first.sessionStart.minute % 15, equals(0));
      expect(sessions.first.sessionEnd, isNull);

      await service.finishFocusSession(
        startTime: start,
        endTime: end,
        interruptions: 1,
        completion: true,
      );

      sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));
      final s = sessions.first;
      expect(s.sessionStart.minute % 15, equals(0));
      expect(s.sessionEnd!.minute % 15, equals(0));
      expect(s.duration, greaterThanOrEqualTo(900));
      expect(s.completion, isTrue);
    });

    test('persists daily brief metrics with non-negative post-processing', () async {
      await service.recordDailyBriefStats(
        '2026-09-09',
        notificationsReviewed: 3,
        actionsCompleted: 1,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 2,
      );

      final brief = await db.dailyBriefDao.getBriefForDate('2026-09-09');
      expect(brief, isNotNull);
      expect(brief!.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(brief.actionsCompleted, greaterThanOrEqualTo(0));
      expect(brief.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(brief.remindersCreated, greaterThanOrEqualTo(0));
      expect(brief.archivedCount, greaterThanOrEqualTo(0));
    });
  });

  group('NotificationController - Telemetry Integration', () {
    test('routes focus sessions through TelemetryGovernanceService', () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );

      final controller = NotificationController(
        telemetryService: service,
        container: container,
      );

      expect(controller.inFocusSession, isFalse);

      await controller.startFocusSession();
      expect(controller.inFocusSession, isTrue);

      var sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));
      expect(sessions.first.sessionStart.minute % 15, equals(0));

      await controller.finishFocusSession();
      expect(controller.inFocusSession, isFalse);

      sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));
      expect(sessions.first.sessionEnd, isNotNull);
      expect(sessions.first.sessionEnd!.minute % 15, equals(0));
      expect(sessions.first.duration % 900, equals(0));

      container.dispose();
    });
  });
}
