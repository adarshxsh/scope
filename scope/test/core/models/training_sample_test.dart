import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/training_sample.dart';

void main() {
  group('TrainingSample Model Tests', () {
    test('TrainingSample round-trip toMap and fromMap preserves fields', () {
      final sample = TrainingSample(
        id: 's1',
        notificationId: 'n100',
        packageName: 'com.whatsapp',
        sanitizedTitle: 'Message from Mom',
        sanitizedContent: 'Please pick up milk',
        featureVector: List.generate(63, (i) => i.toDouble()),
        predictedCategory: 'msg',
        predictedScore: 0.85,
        rewardSignal: 1.0,
        correctedCategory: null,
        correctedPriority: null,
        timestamp: 1700000000000,
        modelVersion: '1.0.0-tflite',
        engineVersion: '2.0.0-hybrid',
      );

      final map = sample.toMap();
      final rehydrated = TrainingSample.fromMap(map);

      expect(rehydrated.id, equals(sample.id));
      expect(rehydrated.notificationId, equals(sample.notificationId));
      expect(rehydrated.featureVector.length, equals(63));
      expect(rehydrated.rewardSignal, equals(1.0));
      expect(rehydrated, equals(sample));
    });

    test('toJsonlMap outputs Python training pipeline compatible JSON schema', () {
      final sample = TrainingSample(
        id: 's2',
        notificationId: 'n101',
        packageName: 'com.hdfcbank',
        sanitizedTitle: 'Account Debit',
        sanitizedContent: 'Rs. [REDACTED_ACCOUNT] debited',
        featureVector: List.filled(63, 0.5),
        predictedCategory: 'finance',
        predictedScore: 0.90,
        rewardSignal: -1.0,
        correctedCategory: 'finance',
        correctedPriority: 'critical',
        timestamp: 1700000000000,
        modelVersion: '1.0.0-tflite',
        engineVersion: '2.0.0-hybrid',
      );

      final jsonlMap = sample.toJsonlMap();

      expect(jsonlMap['id'], equals('s2'));
      expect(jsonlMap['notification_id'], equals('n101'));
      expect(jsonlMap['package_name'], equals('com.hdfcbank'));
      expect(jsonlMap['title'], equals('Account Debit'));
      expect(jsonlMap['category'], equals('finance'));
      expect(jsonlMap['priority'], equals('critical'));
      expect(jsonlMap['look_again_score'], equals(90));
      expect(jsonlMap['reward_signal'], equals(-1.0));
      expect(jsonlMap['features'], isA<List>());
    });
  });
}
