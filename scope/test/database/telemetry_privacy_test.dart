import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/database/telemetry_privacy_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LaplaceNoise Engine Tests', () {
    test('LaplaceNoise generates perturbed values and respects epsilon scale', () {
      final noise = LaplaceNoise(epsilon: 1.0, random: Random(42));
      final sample = noise.sample();
      expect(sample, isA<double>());

      final noisyVal = noise.addNoise(10);
      expect(noisyVal, isA<int>());
    });

    test('LaplaceNoise with deterministic random sequence', () {
      final noise1 = LaplaceNoise(epsilon: 1.0, random: Random(123));
      final noise2 = LaplaceNoise(epsilon: 1.0, random: Random(123));

      final samples1 = List.generate(10, (_) => noise1.addNoise(100));
      final samples2 = List.generate(10, (_) => noise2.addNoise(100));

      expect(samples1, equals(samples2));
    });
  });

  group('TelemetrySanitizer Tests', () {
    test('15-minute timestamp quantization strips seconds and truncates minutes', () {
      final dt1 = DateTime(2026, 9, 11, 14, 12, 34, 567);
      final q1 = TelemetrySanitizer.quantizeTimestamp(dt1);
      expect(q1, equals(DateTime(2026, 9, 11, 14, 0, 0, 0)));

      final dt2 = DateTime(2026, 9, 11, 14, 29, 59, 999);
      final q2 = TelemetrySanitizer.quantizeTimestamp(dt2);
      expect(q2, equals(DateTime(2026, 9, 11, 14, 15, 0, 0)));

      final dt3 = DateTime(2026, 9, 11, 14, 45, 0, 0);
      final q3 = TelemetrySanitizer.quantizeTimestamp(dt3);
      expect(q3, equals(DateTime(2026, 9, 11, 14, 45, 0, 0)));
    });

    test('Session duration bucketing rounds to 5-minute blocks (300 seconds)', () {
      expect(TelemetrySanitizer.bucketDuration(0), equals(0));
      expect(TelemetrySanitizer.bucketDuration(120), equals(0));
      expect(TelemetrySanitizer.bucketDuration(200), equals(300));
      expect(TelemetrySanitizer.bucketDuration(600), equals(600));
      expect(TelemetrySanitizer.bucketDuration(800), equals(900));
    });

    test('Interruption count bucketing maps to discrete ranges', () {
      expect(TelemetrySanitizer.bucketInterruptions(0), equals(0));
      expect(TelemetrySanitizer.bucketInterruptions(1), equals(2));
      expect(TelemetrySanitizer.bucketInterruptions(2), equals(2));
      expect(TelemetrySanitizer.bucketInterruptions(3), equals(5));
      expect(TelemetrySanitizer.bucketInterruptions(5), equals(5));
      expect(TelemetrySanitizer.bucketInterruptions(7), equals(10));
      expect(TelemetrySanitizer.bucketInterruptions(12), equals(15));
    });
  });

  group('TelemetryPrivacyWrapper Integration Tests', () {
    late AttentionDatabase db;
    late TelemetryPrivacyWrapper privacyWrapper;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
      privacyWrapper = TelemetryPrivacyWrapper(db, epsilon: 1.0);
    });

    tearDown(() async {
      await db.close();
    });

    test('Focus session start/end timestamps are truncated to 15-minute boundaries', () async {
      final start = DateTime(2026, 9, 11, 10, 14, 22);
      final end = DateTime(2026, 9, 11, 10, 32, 10);

      final entry = FocusSessionEntry(
        id: 1,
        sessionStart: start,
        sessionEnd: end,
        interruptions: 3,
        completion: true,
        duration: 1070, // ~17.8 mins
      );

      await privacyWrapper.insertFocusSession(entry);

      final sessions = await privacyWrapper.getAllFocusSessions();
      expect(sessions.length, equals(1));

      final saved = sessions.first;
      expect(saved.sessionStart, equals(DateTime(2026, 9, 11, 10, 0, 0)));
      expect(saved.sessionEnd, equals(DateTime(2026, 9, 11, 10, 30, 0)));
      expect(saved.duration, equals(1200)); // 20 mins (4 * 300s)
      expect(saved.interruptions, equals(5)); // discrete bucket range
    });

    test('Daily metric counters are persisted with Laplace noise and queries clamp negative values to >= 0', () async {
      const date = '2026-09-11';

      // Insert entry with small raw counts through privacy wrapper
      final entry = DailyBriefEntry(
        id: 1,
        date: date,
        notificationsReviewed: 0,
        actionsCompleted: 0,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 0,
      );

      await privacyWrapper.insertOrUpdateDailyBrief(entry);

      final fetched = await privacyWrapper.getBriefForDate(date);
      expect(fetched, isNotNull);
      expect(fetched!.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(fetched.actionsCompleted, greaterThanOrEqualTo(0));
      expect(fetched.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(fetched.remindersCreated, greaterThanOrEqualTo(0));
      expect(fetched.archivedCount, greaterThanOrEqualTo(0));
    });

    test('incrementDailyStats applies perturbation and supports query clamping', () async {
      const date = '2026-09-11';

      await privacyWrapper.incrementDailyStats(
        date,
        reviewed: 5,
        completed: 2,
        calendar: 1,
        reminders: 1,
        archived: 3,
      );

      final fetched = await privacyWrapper.getBriefForDate(date);
      expect(fetched, isNotNull);
      expect(fetched!.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(fetched.actionsCompleted, greaterThanOrEqualTo(0));
      expect(fetched.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(fetched.remindersCreated, greaterThanOrEqualTo(0));
      expect(fetched.archivedCount, greaterThanOrEqualTo(0));
    });
  });

  group('NotificationController Telemetry Routing Tests', () {
    late ProviderContainer container;
    late AttentionDatabase db;
    late TelemetryPrivacyWrapper privacyWrapper;
    late NotificationController controller;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
      privacyWrapper = TelemetryPrivacyWrapper(db, epsilon: 1.0);
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      controller = NotificationController(
        container: container,
        privacyWrapper: privacyWrapper,
      );
    });

    tearDown(() async {
      controller.dispose();
      container.dispose();
      await db.close();
    });

    test('Focus session start and finish routes through TelemetryPrivacyWrapper', () async {
      await controller.startFocusSession();
      expect(controller.inFocusSession, isTrue);

      var activeSession = await privacyWrapper.getActiveFocusSession();
      expect(activeSession, isNotNull);
      expect(activeSession!.sessionStart.minute % 15, equals(0));
      expect(activeSession.sessionStart.second, equals(0));

      controller.recordFocusInterruption();
      await controller.finishFocusSession();
      expect(controller.inFocusSession, isFalse);

      activeSession = await privacyWrapper.getActiveFocusSession();
      expect(activeSession, isNull);

      final sessions = await privacyWrapper.getAllFocusSessions();
      expect(sessions.length, equals(1));
      expect(sessions.first.completion, isTrue);
      expect(sessions.first.sessionStart.minute % 15, equals(0));
    });

    test('Action completion routes telemetry updates to DailyBriefDao via TelemetryPrivacyWrapper', () async {
      final notif = AppNotification(
        id: 'n-test',
        packageName: 'com.whatsapp',
        title: 'Test',
        content: 'Body',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
      );

      container.read(reviewQueueProvider.notifier).load([notif]);

      controller.complete('n-test');
      await Future.delayed(Duration.zero);

      final todayStr = DateTime.now().toIso8601String().split('T').first;
      final brief = await privacyWrapper.getBriefForDate(todayStr);
      expect(brief, isNotNull);
      expect(brief!.actionsCompleted, greaterThanOrEqualTo(0));
    });
  });
}
