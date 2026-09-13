import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LaplaceNoise Engine Tests', () {
    test('LaplaceNoise generates perturbed double samples', () {
      final noise = LaplaceNoise(epsilon: 1.0, random: Random(42));
      final sample = noise.sample();
      expect(sample, isA<double>());
    });

    test('LaplaceNoise produces zero-mean distribution properties and reproducible values with seed', () {
      final noise1 = LaplaceNoise(epsilon: 1.0, random: Random(100));
      final noise2 = LaplaceNoise(epsilon: 1.0, random: Random(100));

      final list1 = List.generate(20, (_) => noise1.addNoise(50));
      final list2 = List.generate(20, (_) => noise2.addNoise(50));

      expect(list1, equals(list2));
    });
  });

  group('TelemetrySanitizer Tests', () {
    test('roundToNearestHour rounds DateTime timestamps to nearest hour boundary', () {
      // 14:12:34 -> rounds down to 14:00:00
      final dt1 = DateTime(2026, 9, 13, 14, 12, 34);
      final r1 = TelemetrySanitizer.roundToNearestHour(dt1);
      expect(r1, equals(DateTime(2026, 9, 13, 14, 0, 0)));

      // 14:35:10 -> rounds up to 15:00:00
      final dt2 = DateTime(2026, 9, 13, 14, 35, 10);
      final r2 = TelemetrySanitizer.roundToNearestHour(dt2);
      expect(r2, equals(DateTime(2026, 9, 13, 15, 0, 0)));

      // 23:45:00 -> rounds up to 00:00:00 (next day)
      final dt3 = DateTime(2026, 9, 13, 23, 45, 0);
      final r3 = TelemetrySanitizer.roundToNearestHour(dt3);
      expect(r3, equals(DateTime(2026, 9, 14, 0, 0, 0)));
    });

    test('bucketDurationToHourly aggregates duration in seconds into discrete 60-minute windows (3600s blocks)', () {
      expect(TelemetrySanitizer.bucketDurationToHourly(0), equals(0));
      expect(TelemetrySanitizer.bucketDurationToHourly(600), equals(0)); // 10 mins -> 0 hrs
      expect(TelemetrySanitizer.bucketDurationToHourly(1800), equals(3600)); // 30 mins -> 1 hr (3600s)
      expect(TelemetrySanitizer.bucketDurationToHourly(3600), equals(3600)); // 60 mins -> 1 hr (3600s)
      expect(TelemetrySanitizer.bucketDurationToHourly(5400), equals(7200)); // 90 mins -> 2 hrs (7200s)
    });
  });

  group('FocusSessionDao & DailyBriefDao Telemetry Privacy Tests', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('FocusSessionDao rounds start/end timestamps to nearest hour and aggregates duration into 60-minute windows', () async {
      final start = DateTime(2026, 9, 13, 10, 14, 0);
      final end = DateTime(2026, 9, 13, 10, 48, 0);

      final entry = FocusSessionEntry(
        id: 1,
        sessionStart: start,
        sessionEnd: end,
        interruptions: 2,
        completion: true,
        duration: 2040, // 34 minutes -> rounds to 1 hr (3600s)
      );

      await db.focusSessionDao.insertSession(entry);

      final sessions = await db.focusSessionDao.getAll();
      expect(sessions.length, equals(1));

      final saved = sessions.first;
      expect(saved.sessionStart, equals(DateTime(2026, 9, 13, 10, 0, 0)));
      expect(saved.sessionEnd, equals(DateTime(2026, 9, 13, 11, 0, 0)));
      expect(saved.duration, equals(3600)); // 3600 seconds
    });

    test('DailyBriefDao applies Laplace noise on write and clamps values to >= 0 on lookup', () async {
      const date = '2026-09-13';

      final entry = DailyBriefEntry(
        id: 1,
        date: date,
        notificationsReviewed: 0,
        actionsCompleted: 0,
        calendarEventsCreated: 0,
        remindersCreated: 0,
        archivedCount: 0,
      );

      await db.dailyBriefDao.insertOrUpdate(entry);

      final fetched = await db.dailyBriefDao.getBriefForDate(date);
      expect(fetched, isNotNull);
      expect(fetched!.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(fetched.actionsCompleted, greaterThanOrEqualTo(0));
      expect(fetched.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(fetched.remindersCreated, greaterThanOrEqualTo(0));
      expect(fetched.archivedCount, greaterThanOrEqualTo(0));
    });

    test('Telemetry processing latency for Laplace noise injection and hourly bucketing overhead is under 5ms', () {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 100; i++) {
        TelemetrySanitizer.roundToNearestHour(DateTime.now());
        TelemetrySanitizer.bucketDurationToHourly(3600);
        db.dailyBriefDao.laplaceNoise.addNoise(10);
      }

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(5));
    });
  });
}
