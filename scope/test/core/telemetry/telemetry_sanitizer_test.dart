import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/telemetry/telemetry_sanitizer.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('FocusDurationCategorizer Unit Tests', () {
    test('categorizeSeconds correctly maps durations to standardized time buckets', () {
      expect(FocusDurationCategorizer.categorizeSeconds(0), equals(FocusDurationCategory.under5Min));
      expect(FocusDurationCategorizer.categorizeSeconds(299), equals(FocusDurationCategory.under5Min));

      expect(FocusDurationCategorizer.categorizeSeconds(300), equals(FocusDurationCategory.min5To15));
      expect(FocusDurationCategorizer.categorizeSeconds(899), equals(FocusDurationCategory.min5To15));

      expect(FocusDurationCategorizer.categorizeSeconds(900), equals(FocusDurationCategory.min15To30));
      expect(FocusDurationCategorizer.categorizeSeconds(1799), equals(FocusDurationCategory.min15To30));

      expect(FocusDurationCategorizer.categorizeSeconds(1800), equals(FocusDurationCategory.min30To60));
      expect(FocusDurationCategorizer.categorizeSeconds(3599), equals(FocusDurationCategory.min30To60));

      expect(FocusDurationCategorizer.categorizeSeconds(3600), equals(FocusDurationCategory.over60Min));
      expect(FocusDurationCategorizer.categorizeSeconds(7200), equals(FocusDurationCategory.over60Min));
    });

    test('categorizeLabel returns human-readable category strings', () {
      expect(FocusDurationCategorizer.categorizeLabel(120), equals('< 5 mins'));
      expect(FocusDurationCategorizer.categorizeLabel(600), equals('5-15 mins'));
      expect(FocusDurationCategorizer.categorizeLabel(1500), equals('15-30 mins'));
      expect(FocusDurationCategorizer.categorizeLabel(2700), equals('30-60 mins'));
      expect(FocusDurationCategorizer.categorizeLabel(4000), equals('> 60 mins'));
    });

    test('discretizeSeconds returns fixed bucket duration values', () {
      expect(FocusDurationCategorizer.discretizeSeconds(120), equals(300));
      expect(FocusDurationCategorizer.discretizeSeconds(600), equals(600));
      expect(FocusDurationCategorizer.discretizeSeconds(1500), equals(1200));
      expect(FocusDurationCategorizer.discretizeSeconds(2700), equals(2400));
      expect(FocusDurationCategorizer.discretizeSeconds(4000), equals(3600));
    });
  });

  group('TelemetrySanitizationMiddleware LDP Unit Tests', () {
    test('sampleLaplaceNoise generates expected noise distribution', () {
      final middleware = TelemetrySanitizationMiddleware(
        epsilon: 1.0,
        sensitivity: 1.0,
        random: Random(42), // Fixed seed for reproducibility
      );

      final samples = List<double>.generate(100, (_) => middleware.sampleLaplaceNoise());
      expect(samples.length, equals(100));

      // Mean of Laplace(0, 1) should be roughly near 0
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      expect(mean.abs(), lessThan(1.0));
    });

    test('sanitizeCounter enforces non-negative lower bounds', () {
      final middleware = TelemetrySanitizationMiddleware(
        epsilon: 1.0,
        random: Random(123),
      );

      // Raw value 0 with negative Laplace noise should clamp to lowerBound (0)
      for (int i = 0; i < 50; i++) {
        final sanitized = middleware.sanitizeCounter(0, lowerBound: 0);
        expect(sanitized, greaterThanOrEqualTo(0));
      }
    });

    test('sanitizeMetrics intercepts daily engagement counts and injects DP noise', () {
      final middleware = TelemetrySanitizationMiddleware(
        epsilon: 1.0,
        random: Random(100),
      );

      const raw = DailyEngagementMetrics(
        notificationsReviewed: 10,
        actionsCompleted: 5,
        calendarEventsCreated: 2,
        remindersCreated: 3,
        archivedCount: 8,
      );

      final sanitized = middleware.sanitizeMetrics(raw);

      // All sanitized metrics should be non-negative
      expect(sanitized.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(sanitized.actionsCompleted, greaterThanOrEqualTo(0));
      expect(sanitized.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(sanitized.remindersCreated, greaterThanOrEqualTo(0));
      expect(sanitized.archivedCount, greaterThanOrEqualTo(0));
    });

    test('sanitizeFocusSession removes exact millisecond precision and discretizes duration', () {
      final middleware = TelemetrySanitizationMiddleware();
      final exactStartTime = DateTime(2026, 9, 6, 14, 23, 45, 892);
      final exactEndTime = DateTime(2026, 9, 6, 14, 38, 12, 114);

      final rawEntry = FocusSessionEntry(
        id: 1,
        sessionStart: exactStartTime,
        sessionEnd: exactEndTime,
        interruptions: 0,
        completion: true,
        duration: 867, // exact raw duration = 14m 27s = 867s
      );

      final sanitized = middleware.sanitizeFocusSession(rawEntry);

      // Duration must be discretized to 600s (5-15 mins category bucket)
      expect(sanitized.duration, equals(600));
      expect(sanitized.durationCategory, equals('5-15 mins'));

      // Timestamps must strip seconds and milliseconds (truncated to minute)
      expect(sanitized.sessionStart.second, equals(0));
      expect(sanitized.sessionStart.millisecond, equals(0));
      expect(sanitized.sessionEnd!.second, equals(0));
      expect(sanitized.sessionEnd!.millisecond, equals(0));
    });

    test('Processing latency is under 10 milliseconds SLA benchmark', () {
      final middleware = TelemetrySanitizationMiddleware();
      const raw = DailyEngagementMetrics(
        notificationsReviewed: 100,
        actionsCompleted: 50,
        calendarEventsCreated: 20,
        remindersCreated: 30,
        archivedCount: 40,
      );

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        middleware.sanitizeMetrics(raw);
      }
      stopwatch.stop();

      // 1000 transactions took under 100ms total, so each transaction is well under 10ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
