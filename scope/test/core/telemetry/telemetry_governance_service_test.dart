import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/telemetry/telemetry_governance_service.dart';

void main() {
  group('TelemetryGovernanceService Unit Tests', () {
    test('quantizeTimestamp rounds timestamps down to 15-minute epoch intervals', () {
      final constTimestamp = DateTime(2026, 9, 17, 10, 23, 45).millisecondsSinceEpoch;
      final quantized = TelemetryGovernanceService.quantizeTimestamp(constTimestamp);
      
      final expectedDateTime = DateTime(2026, 9, 17, 10, 15, 0).millisecondsSinceEpoch;
      expect(quantized, equals(expectedDateTime));
    });

    test('quantizeDuration rounds seconds to standard bucket size', () {
      expect(TelemetryGovernanceService.quantizeDuration(125, bucketSizeSeconds: 60), equals(120));
      expect(TelemetryGovernanceService.quantizeDuration(59, bucketSizeSeconds: 60), equals(0));
      expect(TelemetryGovernanceService.quantizeDuration(310, bucketSizeSeconds: 300), equals(300));
    });

    test('quantizeInterruptions rounds count to step size', () {
      expect(TelemetryGovernanceService.quantizeInterruptions(7, step: 5), equals(5));
      expect(TelemetryGovernanceService.quantizeInterruptions(2, step: 1), equals(2));
    });

    test('addNoisyCount injects Laplace noise and clamps results to non-negative integers', () {
      // Deterministic Random returning 0.5 (center) -> zero noise
      final fixedRng = math.Random(42);
      final noisyVal = TelemetryGovernanceService.addNoisyCount(
        10,
        sensitivity: 1.0,
        epsilon: 0.5,
        random: fixedRng,
      );
      expect(noisyVal, greaterThanOrEqualTo(0));

      // Test extreme negative noise clamping
      final zeroVal = TelemetryGovernanceService.addNoisyCount(
        0,
        sensitivity: 10.0,
        epsilon: 0.1,
        random: fixedRng,
      );
      expect(zeroVal, greaterThanOrEqualTo(0));
    });

    test('applyDifferentialPrivacyToDailyBrief produces non-negative noisy stats', () {
      final service = TelemetryGovernanceService();
      final stats = service.applyDifferentialPrivacyToDailyBrief(
        notificationsReviewed: 20,
        actionsCompleted: 5,
        calendarEventsCreated: 2,
        remindersCreated: 1,
        archivedCount: 15,
        random: math.Random(12345),
      );

      expect(stats.keys, containsAll([
        'notificationsReviewed',
        'actionsCompleted',
        'calendarEventsCreated',
        'remindersCreated',
        'archivedCount',
      ]));

      for (final val in stats.values) {
        expect(val, greaterThanOrEqualTo(0));
      }
    });


    test('privacy budget tracker enforces cumulative maxEpsilon budget limits', () {
      final service = TelemetryGovernanceService(maxEpsilon: 2.0);
      const entity = 'daily_brief_aggregator';

      expect(service.getRemainingBudget(entity), equals(2.0));
      expect(service.canConsumeBudget(entity, 0.5), isTrue);

      expect(service.consumeBudget(entity, 1.2), isTrue);
      expect(service.getRemainingBudget(entity), closeTo(0.8, 1e-5));

      expect(service.consumeBudget(entity, 0.9), isFalse); // Exceeds 0.8
      expect(service.getRemainingBudget(entity), closeTo(0.8, 1e-5));

      service.resetBudget(entity);
      expect(service.getRemainingBudget(entity), equals(2.0));
    });
  });
}
