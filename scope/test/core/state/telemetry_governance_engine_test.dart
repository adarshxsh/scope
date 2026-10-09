import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:scope/core/state/telemetry_governance_engine.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('TelemetryGovernanceEngine Unit Tests', () {
    late TelemetryGovernanceEngine engine;

    setUp(() {
      engine = TelemetryGovernanceEngine(epsilon: 0.5);
    });

    group('15-Minute Temporal Rounding (roundTo15Minutes)', () {
      test('leaves exact 15-minute boundary timestamps untouched', () {
        final t1 = DateTime(2026, 9, 19, 10, 0, 0);
        final t2 = DateTime(2026, 9, 19, 10, 15, 0);
        final t3 = DateTime(2026, 9, 19, 10, 30, 0);
        final t4 = DateTime(2026, 9, 19, 10, 45, 0);

        expect(engine.roundTo15Minutes(t1), equals(t1));
        expect(engine.roundTo15Minutes(t2), equals(t2));
        expect(engine.roundTo15Minutes(t3), equals(t3));
        expect(engine.roundTo15Minutes(t4), equals(t4));
      });

      test('rounds timestamps under 7m30s down to previous 15-minute boundary', () {
        final dt = DateTime(2026, 9, 19, 10, 7, 29);
        final expected = DateTime(2026, 9, 19, 10, 0, 0);
        expect(engine.roundTo15Minutes(dt), equals(expected));
      });

      test('rounds timestamps at or above 7m30s up to next 15-minute boundary', () {
        final dt = DateTime(2026, 9, 19, 10, 7, 30);
        final expected = DateTime(2026, 9, 19, 10, 15, 0);
        expect(engine.roundTo15Minutes(dt), equals(expected));
      });

      test('rounds timestamps near hour wrap correctly across hours', () {
        final dt = DateTime(2026, 9, 19, 10, 53, 0);
        final expected = DateTime(2026, 9, 19, 11, 0, 0);
        expect(engine.roundTo15Minutes(dt), equals(expected));
      });

      test('rounds timestamps across day and year boundaries', () {
        final dt = DateTime(2026, 12, 31, 23, 53, 0);
        final expected = DateTime(2027, 1, 1, 0, 0, 0);
        expect(engine.roundTo15Minutes(dt), equals(expected));
      });
    });

    group('5-Minute Duration Quantization (quantizeDurationSeconds)', () {
      test('quantizes duration in seconds to 5-minute (300-second) bins', () {
        expect(engine.quantizeDurationSeconds(0), equals(0));
        expect(engine.quantizeDurationSeconds(100), equals(0)); // 1.6 min -> 0 min
        expect(engine.quantizeDurationSeconds(150), equals(300)); // 2.5 min -> 5 min (300s)
        expect(engine.quantizeDurationSeconds(299), equals(300)); // 4.9 min -> 5 min (300s)
        expect(engine.quantizeDurationSeconds(300), equals(300)); // 5 min -> 300s
        expect(engine.quantizeDurationSeconds(700), equals(600)); // 11.6 min -> 10 min (600s)
        expect(engine.quantizeDurationSeconds(800), equals(900)); // 13.3 min -> 15 min (900s)
      });

      test('handles negative duration gracefully by returning 0', () {
        expect(engine.quantizeDurationSeconds(-120), equals(0));
      });
    });

    group('Laplace Noise Injection & Clamping', () {
      test('default privacy parameter epsilon is 0.5', () {
        expect(engine.epsilon, equals(0.5));
      });

      test('applies Laplace noise using inverse transform sampling and clamps to non-negative', () {
        final customRandom = math.Random(42); // Seeded random for deterministic behavior
        final noisy = engine.applyLaplaceNoise(5, random: customRandom);
        expect(noisy, isA<int>());
        expect(noisy, greaterThanOrEqualTo(0));
      });

      test('clamps noisy output to zero if noise causes negative value', () {
        // Create a fake random that produces small u to simulate large negative noise
        final mockRandom = _ConstantRandom(0.0001); // u - 0.5 = -0.4999 -> negative noise
        final noisy = engine.applyLaplaceNoise(1, random: mockRandom);
        expect(noisy, equals(0));
      });
    });

    group('Entry Governance Methods', () {
      test('governFocusSession aligns timestamps and quantizes duration', () {
        final entry = FocusSessionEntry(
          id: 1,
          sessionStart: DateTime(2026, 9, 19, 10, 7, 45), // Should round to 10:15
          sessionEnd: DateTime(2026, 9, 19, 10, 22, 10),  // Should round to 10:22 -> 10:15 or 10:30? 22.16 min -> 22 min 10s -> 22.16 / 15 = 1.47 -> 1 -> 10:15
          interruptions: 2,
          completion: true,
          duration: 720, // 12 minutes -> should quantize to 10 minutes (600 seconds)
        );

        final governed = engine.governFocusSession(entry);
        expect(governed.sessionStart, equals(DateTime(2026, 9, 19, 10, 15, 0)));
        expect(governed.sessionEnd, equals(DateTime(2026, 9, 19, 10, 15, 0)));
        expect(governed.duration, equals(600));
        expect(governed.interruptions, equals(2));
        expect(governed.completion, isTrue);
      });

      test('governDailyBrief applies noise and clamps all activity counters', () {
        final mockRandom = math.Random(123);
        final entry = DailyBriefEntry(
          id: 1,
          date: '2026-09-19',
          notificationsReviewed: 10,
          actionsCompleted: 5,
          calendarEventsCreated: 2,
          remindersCreated: 1,
          archivedCount: 3,
        );

        final governed = engine.governDailyBrief(entry, random: mockRandom);
        expect(governed.notificationsReviewed, greaterThanOrEqualTo(0));
        expect(governed.actionsCompleted, greaterThanOrEqualTo(0));
        expect(governed.calendarEventsCreated, greaterThanOrEqualTo(0));
        expect(governed.remindersCreated, greaterThanOrEqualTo(0));
        expect(governed.archivedCount, greaterThanOrEqualTo(0));
      });
    });
  });
}

class _ConstantRandom implements math.Random {
  final double value;
  _ConstantRandom(this.value);

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => value >= 0.5;

  @override
  int nextInt(int max) => (value * max).floor();
}
