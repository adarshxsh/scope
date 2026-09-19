import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/federated/federated_learning_client.dart';
import 'package:scope/core/federated/privacy_budget_tracker.dart';

void main() {
  group('PrivacyBudgetTracker Tests', () {
    test('initializes with default budget parameters', () {
      final tracker = PrivacyBudgetTracker();
      expect(tracker.maxEpsilon, equals(2.0));
      expect(tracker.consumedEpsilon, equals(0.0));
      expect(tracker.remainingEpsilon, equals(2.0));
      expect(tracker.isBudgetExhausted, isFalse);
    });

    test('deducts budget accurately', () {
      final tracker = PrivacyBudgetTracker(maxEpsilon: 1.0);
      tracker.consume(0.3);
      expect(tracker.consumedEpsilon, closeTo(0.3, 1e-6));
      expect(tracker.remainingEpsilon, closeTo(0.7, 1e-6));

      tracker.consume(0.7);
      expect(tracker.consumedEpsilon, closeTo(1.0, 1e-6));
      expect(tracker.isBudgetExhausted, isTrue);
    });

    test('throws PrivacyBudgetExhaustedException when budget is exceeded', () {
      final tracker = PrivacyBudgetTracker(maxEpsilon: 0.5);
      tracker.consume(0.4);

      expect(
        () => tracker.consume(0.2),
        throwsA(isA<PrivacyBudgetExhaustedException>()),
      );
    });

    test('resets epoch window correctly', () {
      final tracker = PrivacyBudgetTracker(maxEpsilon: 1.0);
      tracker.consume(0.8);
      expect(tracker.consumedEpsilon, closeTo(0.8, 1e-6));

      tracker.resetEpoch();
      expect(tracker.consumedEpsilon, equals(0.0));
      expect(tracker.isBudgetExhausted, isFalse);
    });
  });

  group('FederatedLearningClient Tests', () {
    late FederatedLearningClient client;
    late PrivacyBudgetTracker tracker;

    setUp(() {
      tracker = PrivacyBudgetTracker(maxEpsilon: 2.0);
      client = FederatedLearningClient(
        privacyBudgetTracker: tracker,
        clippingThresholdC: 1.0,
        defaultEpsilonStep: 0.1,
      );
    });

    test('validates 63-dimensional feature vector input', () {
      final invalidVector = List<double>.filled(10, 0.5);
      expect(
        () => client.computeGradientUpdate(
          featureVector: invalidVector,
          predictedScore: 0.8,
          targetScore: 0.2,
        ),
        throwsArgumentError,
      );
    });

    test('validates non-finite score and feature inputs', () {
      final validVector = List<double>.filled(63, 0.5);

      expect(
        () => client.computeGradientUpdate(
          featureVector: validVector,
          predictedScore: double.nan,
          targetScore: 0.5,
        ),
        throwsArgumentError,
      );

      expect(
        () => client.computeGradientUpdate(
          featureVector: validVector,
          predictedScore: 0.5,
          targetScore: double.infinity,
        ),
        throwsArgumentError,
      );

      final nanVector = List<double>.filled(63, 0.5);
      nanVector[10] = double.nan;
      expect(
        () => client.computeGradientUpdate(
          featureVector: nanVector,
          predictedScore: 0.5,
          targetScore: 0.2,
        ),
        throwsArgumentError,
      );
    });

    test('enforces maxBufferSize memory quota using FIFO eviction', () {
      final cappedClient = FederatedLearningClient(
        privacyBudgetTracker: PrivacyBudgetTracker(maxEpsilon: 100.0),
        maxBufferSize: 3,
        defaultEpsilonStep: 0.01,
      );

      final vector = List<double>.filled(63, 0.1);

      for (int i = 0; i < 5; i++) {
        cappedClient.computeGradientUpdate(
          featureVector: vector,
          predictedScore: 0.5,
          targetScore: 0.1,
        );
      }

      // Buffer size must be capped at maxBufferSize (3)
      expect(cappedClient.bufferedUpdates.length, equals(3));
    });

    test('computes gradient, applies L2 norm clipping and noise injection', () {
      final featureVector = List<double>.generate(63, (i) => (i + 1) * 0.1);
      final update = client.computeGradientUpdate(
        featureVector: featureVector,
        predictedScore: 0.9,
        targetScore: 0.1,
        epsilonStep: 0.2,
        useGaussianNoise: false, // Laplace for deterministic bounds testing
      );

      expect(update.gradientDelta.length, equals(63));
      expect(update.l2NormBeforeClipping, greaterThan(1.0));
      expect(update.l2NormAfterClipping, closeTo(1.0, 1e-5));
      expect(update.epsilonUsed, equals(0.2));
      expect(tracker.consumedEpsilon, closeTo(0.2, 1e-6));
    });

    test('enforces privacy budget check and halts when exhausted', () {
      final smallTracker = PrivacyBudgetTracker(maxEpsilon: 0.15);
      final clientWithSmallBudget = FederatedLearningClient(
        privacyBudgetTracker: smallTracker,
        defaultEpsilonStep: 0.1,
      );

      final featureVector = List<double>.filled(63, 0.5);

      // First step succeeds (0.1 consumed)
      clientWithSmallBudget.computeGradientUpdate(
        featureVector: featureVector,
        predictedScore: 0.7,
        targetScore: 0.2,
      );

      // Second step fails (0.1 + 0.1 = 0.2 > 0.15)
      expect(
        () => clientWithSmallBudget.computeGradientUpdate(
          featureVector: featureVector,
          predictedScore: 0.7,
          targetScore: 0.2,
        ),
        throwsA(isA<PrivacyBudgetExhaustedException>()),
      );
    });

    test('enforces device state guardrails for sync', () {
      final featureVector = List<double>.filled(63, 0.1);
      client.computeGradientUpdate(
        featureVector: featureVector,
        predictedScore: 0.5,
        targetScore: 0.1,
      );

      expect(client.bufferedUpdates.length, equals(1));

      // Disconnected Wi-Fi -> sync should be blocked
      client.setDeviceState(isWifiConnected: false, isCharging: true);
      final emptyExport = client.exportAndClearBufferedUpdates();
      expect(emptyExport, isEmpty);
      expect(client.bufferedUpdates.length, equals(1));

      // Connected Wi-Fi + Charging -> sync allowed
      client.setDeviceState(isWifiConnected: true, isCharging: true);
      final exported = client.exportAndClearBufferedUpdates();
      expect(exported.length, equals(1));
      expect(client.bufferedUpdates, isEmpty);
    });

    test('serializes ClientGradientUpdate to JSON without PII', () {
      final featureVector = List<double>.filled(63, 0.2);
      final update = client.computeGradientUpdate(
        featureVector: featureVector,
        predictedScore: 0.8,
        targetScore: 0.3,
      );

      final json = update.toJson();
      expect(json.containsKey('update_id'), isTrue);
      expect(json.containsKey('gradient_delta'), isTrue);
      expect((json['gradient_delta'] as List).length, equals(63));

      // Verify no PII fields present
      expect(json.containsKey('title'), isFalse);
      expect(json.containsKey('content'), isFalse);
      expect(json.containsKey('package_name'), isFalse);
    });
  });
}
