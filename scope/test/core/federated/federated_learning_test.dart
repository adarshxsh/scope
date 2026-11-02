import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/federated/differential_privacy.dart';
import 'package:scope/core/federated/federated_learning.dart';

void main() {
  group('FederatedLearningManager Unit & Integration Tests', () {
    late FederatedLearningManager flManager;

    setUp(() {
      flManager = FederatedLearningManager(
        initialWeights: List.filled(63, 0.1),
        dp: DifferentialPrivacy(
          config: const DifferentialPrivacyConfig(
            clipNorm: 1.0,
            noiseMultiplier: 0.1,
            targetEpsilon: 2.0,
            targetDelta: 1e-5,
            maxPrivacyBudgetEpsilon: 10.0,
          ),
        ),
        learningRate: 0.05,
      );
    });

    test('computeLocalUpdate executes successfully on valid inputs', () {
      final features = [
        List.filled(63, 1.0),
        List.filled(63, 0.5),
      ];
      final targets = [1.0, 0.0];

      final result = flManager.computeLocalUpdate(
        features: features,
        targets: targets,
        roundId: 'round-1',
      );

      expect(result.success, isTrue);
      expect(result.roundId, equals('round-1'));
      expect(result.updatedWeights, isNotNull);
      expect(result.updatedWeights!.length, equals(63));
      expect(result.auditLog.status, equals('success'));
      expect(flManager.completedRounds, equals(1));
      expect(flManager.auditLogs.length, equals(1));
    });

    test('computeLocalUpdate handles empty features or mismatched targets gracefully', () {
      final resultEmpty = flManager.computeLocalUpdate(
        features: [],
        targets: [],
        roundId: 'round-empty',
      );

      expect(resultEmpty.success, isFalse);
      expect(resultEmpty.auditLog.status, equals('fallback_invalid_inputs'));

      final resultMismatch = flManager.computeLocalUpdate(
        features: [List.filled(63, 1.0)],
        targets: [1.0, 0.0], // 1 feature row, 2 target elements
        roundId: 'round-mismatch',
      );

      expect(resultMismatch.success, isFalse);
      expect(resultMismatch.auditLog.status, equals('fallback_invalid_inputs'));
    });

    test('computeLocalUpdate triggers fallback error recovery on NaN or Infinity in inputs', () {
      final invalidFeatures = [
        List.generate(63, (i) => i == 10 ? double.nan : 0.5),
      ];
      final targets = [1.0];

      final result = flManager.computeLocalUpdate(
        features: invalidFeatures,
        targets: targets,
        roundId: 'round-nan',
      );

      expect(result.success, isFalse);
      expect(result.auditLog.status, equals('fallback_error'));
      expect(result.errorMessage, contains('non-finite'));
      // Ensure base weights were NOT corrupted
      expect(flManager.currentWeights, equals(List.filled(63, 0.1)));
    });

    test('computeLocalUpdate halts training when max privacy budget epsilon is exceeded', () {
      // Create a manager with a very low budget limit (0.01)
      final lowBudgetManager = FederatedLearningManager(
        initialWeights: List.filled(63, 0.1),
        dp: DifferentialPrivacy(
          config: const DifferentialPrivacyConfig(
            clipNorm: 1.0,
            noiseMultiplier: 0.1,
            maxPrivacyBudgetEpsilon: 0.0001,
          ),
        ),
      );

      // Perform round 1
      lowBudgetManager.computeLocalUpdate(
        features: [List.filled(63, 0.5)],
        targets: [1.0],
        roundId: 'round-1',
      );

      // Round 2 should be blocked by budget
      final resultBlocked = lowBudgetManager.computeLocalUpdate(
        features: [List.filled(63, 0.5)],
        targets: [1.0],
        roundId: 'round-2',
      );

      expect(resultBlocked.success, isFalse);
      expect(resultBlocked.auditLog.status, equals('fallback_privacy_budget_exceeded'));
    });

    test('computeLocalUpdate sanitizes PII in roundId and audit log details', () {
      final features = [List.filled(63, 0.5)];
      final targets = [1.0];

      final result = flManager.computeLocalUpdate(
        features: features,
        targets: targets,
        roundId: 'round-user-secret@test.com',
      );

      expect(result.roundId, contains('[REDACTED_EMAIL]'));
      expect(result.roundId, isNot(contains('secret@test.com')));
      expect(result.auditLog.details, isNot(contains('secret@test.com')));
    });

    test('auditLogs caps entry history and supports clearing', () {
      final smallLogManager = FederatedLearningManager(
        initialWeights: List.filled(63, 0.1),
        maxAuditLogEntries: 3,
      );

      for (int i = 0; i < 5; i++) {
        smallLogManager.computeLocalUpdate(
          features: [List.filled(63, 0.1)],
          targets: [1.0],
          roundId: 'round-$i',
        );
      }

      expect(smallLogManager.auditLogs.length, equals(3));
      expect(smallLogManager.auditLogs.last.roundId, equals('round-4'));

      smallLogManager.clearAuditLogs();
      expect(smallLogManager.auditLogs, isEmpty);
    });
  });
}
