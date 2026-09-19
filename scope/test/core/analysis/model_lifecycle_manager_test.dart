import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_lifecycle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_lifecycle_test_');
    ModelLifecycleManager.instance.setCustomBaseDirectory(tempDir);
    await ModelLifecycleManager.instance.clearFeedbackSamples();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelLifecycleManager RLHF Logging Tests', () {
    test('logFeedbackSample persists sample to memory and jsonl file', () async {
      final sample = RLHFFeedbackSample(
        id: 'test-rlhf-1',
        notificationId: 'notif-100',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your code is 123456',
        featureVector: List<double>.filled(63, 0.5),
        predictedCategory: 'system',
        predictedPriority: 'high',
        predictedScore: 0.85,
        rewardSignal: 1.0,
        modelVersion: '1.0.0-tflite',
        ruleVersion: '1.0.0',
        timestamp: 1620000000000,
      );

      await ModelLifecycleManager.instance.logFeedbackSample(sample);

      expect(ModelLifecycleManager.instance.feedbackSamplesCount, 1);
      final samples = await ModelLifecycleManager.instance.loadFeedbackSamples();
      expect(samples.length, 1);
      expect(samples.first.id, 'test-rlhf-1');
      expect(samples.first.rewardSignal, 1.0);
      expect(samples.first.packageName, 'com.whatsapp');
    });

    test('exportFeedbackDatasetJsonl outputs valid jsonl string', () async {
      final sample = RLHFFeedbackSample(
        id: 'test-rlhf-2',
        notificationId: 'notif-200',
        packageName: 'com.bank.app',
        title: 'Debit Alert',
        content: 'Rs. 500 debited',
        featureVector: List<double>.filled(63, 0.1),
        predictedCategory: 'financial',
        predictedPriority: 'high',
        predictedScore: 0.80,
        rewardSignal: -1.0,
        correctedCategory: 'financial',
        correctedPriority: 'critical',
        correctedScore: 1.0,
        modelVersion: '1.0.0-tflite',
        ruleVersion: '1.0.0',
        timestamp: 1620000005000,
      );

      await ModelLifecycleManager.instance.logFeedbackSample(sample);
      final jsonl = await ModelLifecycleManager.instance.exportFeedbackDatasetJsonl();

      expect(jsonl, contains('test-rlhf-2'));
      expect(jsonl, contains('corrected_priority":"critical"'));
    });

    test('clearFeedbackSamples removes all samples', () async {
      final sample = RLHFFeedbackSample(
        id: 'test-rlhf-3',
        notificationId: 'notif-300',
        packageName: 'com.test',
        title: 'Title',
        content: 'Content',
        featureVector: List<double>.filled(63, 0.0),
        predictedCategory: 'unknown',
        predictedPriority: 'medium',
        predictedScore: 0.5,
        rewardSignal: 1.0,
        modelVersion: '1.0.0-tflite',
        ruleVersion: '1.0.0',
        timestamp: 1620000010000,
      );

      await ModelLifecycleManager.instance.logFeedbackSample(sample);
      expect(ModelLifecycleManager.instance.feedbackSamplesCount, 1);

      await ModelLifecycleManager.instance.clearFeedbackSamples();
      expect(ModelLifecycleManager.instance.feedbackSamplesCount, 0);

      final samples = await ModelLifecycleManager.instance.loadFeedbackSamples();
      expect(samples.isEmpty, isTrue);
    });
  });

  group('ModelLifecycleManager Validation & Deployment Tests', () {
    test('validateCandidateModel rejects empty model bytes', () async {
      final isValid = await ModelLifecycleManager.instance.validateCandidateModel(
        modelBytes: Uint8List(0),
        candidateVersion: '2.0.0',
      );
      expect(isValid, isFalse);
    });

    test('validateCandidateModel rejects corrupt model bytes', () async {
      final isValid = await ModelLifecycleManager.instance.validateCandidateModel(
        modelBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        candidateVersion: '2.0.0',
      );
      expect(isValid, isFalse);
    });

    test('validateCandidateModel rejects older or invalid candidate versions', () async {
      final isValid = await ModelLifecycleManager.instance.validateCandidateModel(
        modelBytes: Uint8List.fromList([0, 1, 2]),
        candidateVersion: '0.9.0', // Older than active '1.0.0-tflite'
      );
      expect(isValid, isFalse);
    });

    test('rollbackToDefaultAsset restores activeVersion to default', () async {
      await ModelLifecycleManager.instance.rollbackToDefaultAsset();
      expect(ModelLifecycleManager.instance.activeVersion, ModelLifecycleManager.defaultAssetVersion);
      expect(ModelLifecycleManager.instance.activeModelFile, isNull);
    });
  });
}
