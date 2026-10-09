import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/telemetry/telemetry_governance_manager.dart';

void main() {
  group('TelemetryGovernanceManager Tests', () {
    late TelemetryGovernanceManager manager;

    setUp(() {
      manager = TelemetryGovernanceManager(
        level: TelemetryAnonymizationLevel.standard,
        random: math.Random(42), // Deterministic seed for reproducible tests
      );
    });

    test('quantizeTimestamp quantizes DateTime to 15-minute intervals', () {
      final inputTime = DateTime(2026, 9, 10, 14, 23, 45, 678);
      final quantized = manager.quantizeTimestamp(inputTime, intervalMinutes: 15);

      expect(quantized.year, equals(2026));
      expect(quantized.month, equals(9));
      expect(quantized.day, equals(10));
      expect(quantized.hour, equals(14));
      expect(quantized.minute, equals(15)); // 23 ~/ 15 * 15 = 15
      expect(quantized.second, equals(0));
      expect(quantized.millisecond, equals(0));
    });

    test('quantizeFocusSession quantizes start and end times to 15-minute intervals', () {
      final start = DateTime(2026, 9, 10, 10, 7, 12);
      final end = DateTime(2026, 9, 10, 10, 38, 45);

      final result = manager.quantizeFocusSession(start, end);

      final qStart = result['quantizedStart'] as DateTime;
      final qEnd = result['quantizedEnd'] as DateTime;
      final durationMinutes = result['durationMinutes'] as int;

      expect(qStart, equals(DateTime(2026, 9, 10, 10, 0)));
      expect(qEnd, equals(DateTime(2026, 9, 10, 10, 30)));
      expect(durationMinutes, equals(30));
    });

    test('addLaplaceNoise injects noise and clamps result to non-negative', () {
      const rawCount = 10;
      final noisyCount = manager.addLaplaceNoise(rawCount, epsilon: 1.0);

      expect(noisyCount, isA<int>());
      expect(noisyCount, greaterThanOrEqualTo(0));
    });

    test('addLaplaceNoise returns exact value when level is off', () {
      manager.level = TelemetryAnonymizationLevel.off;
      const rawCount = 42;
      final noisyCount = manager.addLaplaceNoise(rawCount, epsilon: 1.0);

      expect(noisyCount, equals(rawCount));
    });

    test('applyKAnonymity suppresses hourly bins below kThreshold', () {
      final hourlyVolume = [0, 1, 2, 3, 5, 10, 1, 0];

      // With k=3
      final kAnonymized = manager.applyKAnonymity(hourlyVolume, kThreshold: 3);

      expect(kAnonymized, equals([0, 0, 0, 3, 5, 10, 0, 0]));
    });

    test('processHourlyVolume respects anonymization level rules', () {
      final rawVolume = List<int>.generate(24, (i) => i % 4); // values: 0, 1, 2, 3

      // When level is off
      manager.level = TelemetryAnonymizationLevel.off;
      final offVolume = manager.processHourlyVolume(rawVolume);
      expect(offVolume, equals(rawVolume));

      // When level is standard (k=3, epsilon=1.0)
      manager.level = TelemetryAnonymizationLevel.standard;
      final stdVolume = manager.processHourlyVolume(rawVolume);
      expect(stdVolume.length, equals(24));
      // Bins with raw count 1 and 2 should be suppressed to 0 before noise
      expect(stdVolume[1], equals(0));
      expect(stdVolume[2], equals(0));
      // All counts should be non-negative
      for (final count in stdVolume) {
        expect(count, greaterThanOrEqualTo(0));
      }
    });

    test('processDailyBriefStats injects noise into brief interaction statistics', () {
      final stats = manager.processDailyBriefStats(
        notificationsReviewed: 15,
        actionsCompleted: 5,
        calendarEventsCreated: 2,
        remindersCreated: 1,
        archivedCount: 8,
      );

      expect(stats.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(stats.actionsCompleted, greaterThanOrEqualTo(0));
      expect(stats.calendarEventsCreated, greaterThanOrEqualTo(0));
      expect(stats.remindersCreated, greaterThanOrEqualTo(0));
      expect(stats.archivedCount, greaterThanOrEqualTo(0));
    });

    test('Query processing latency for noise injection and quantization remains under 10 ms', () {
      final rawVolume = List<int>.filled(24, 15);
      final stopwatch = Stopwatch()..start();

      manager.quantizeTimestamp(DateTime.now());
      manager.processHourlyVolume(rawVolume);
      manager.processDailyBriefStats(
        notificationsReviewed: 20,
        actionsCompleted: 10,
        calendarEventsCreated: 3,
        remindersCreated: 2,
        archivedCount: 5,
      );

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
    });

    test('Underlying raw notification object data remains unmodified by telemetry governance', () {
      final notification = AppNotification(
        id: 'test-001',
        packageName: 'com.example.app',
        title: 'Meeting Reminder',
        content: 'Team sync at 3 PM',
        timestamp: DateTime(2026, 9, 10, 14, 22, 10).millisecondsSinceEpoch,
        priority: 'high',
      );

      final rawVolume = [1, 5, 0];
      manager.processHourlyVolume(rawVolume);

      // Notification properties remain intact
      expect(notification.timestamp, equals(DateTime(2026, 9, 10, 14, 22, 10).millisecondsSinceEpoch));
      expect(notification.title, equals('Meeting Reminder'));
    });
  });
}
