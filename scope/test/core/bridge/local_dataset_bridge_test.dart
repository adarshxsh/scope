import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/local_dataset_bridge.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalDatasetBridge Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dataset_bridge_test_');
      LocalDatasetBridge.instance.clearFeedback();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('recordFeedback stores and retrieves feedback entries', () async {
      await LocalDatasetBridge.instance.recordFeedback(
        notificationId: 'notif-1',
        action: 'reward',
        customTargetScore: 1.0,
      );

      final store = LocalDatasetBridge.instance.feedbackStore;
      expect(store.containsKey('notif-1'), isTrue);
      expect(store['notif-1']?.feedbackAction, equals('reward'));
      expect(store['notif-1']?.customTargetScore, equals(1.0));
    });

    test('exportTrainingDataset creates structured JSONL dataset file without raw text', () async {
      final notifs = [
        AppNotification(
          id: 'n-1',
          packageName: 'com.whatsapp',
          title: 'Verification Code',
          content: 'Your OTP is 123456',
          timestamp: 1620000000000,
          priority: 'critical',
          priorityScore: 0.95,
          classifiedCategory: 'sys',
          modelVersion: '1.0.0-tflite (local_storage)',
        ),
        AppNotification(
          id: 'n-2',
          packageName: 'com.shopping.app',
          title: 'Mega Sale Today',
          content: 'Get 50% discount on all items',
          timestamp: 1620000100000,
          priority: 'low',
          priorityScore: 0.10,
          classifiedCategory: 'promo',
          modelVersion: '1.0.0-tflite (local_storage)',
        ),
      ];

      // Record feedback for n-1
      await LocalDatasetBridge.instance.recordFeedback(
        notificationId: 'n-1',
        action: 'reward',
        customTargetScore: 1.0,
      );

      final exportPath = '${tempDir.path}/export_test.jsonl';
      final exportedFile = await LocalDatasetBridge.instance.exportTrainingDataset(
        notifications: notifs,
        outputPath: exportPath,
      );

      expect(exportedFile.existsSync(), isTrue);
      final lines = await exportedFile.readAsLines();
      expect(lines.length, equals(2));

      // Parse first line (n-1 with reward feedback)
      final record1 = json.decode(lines[0]) as Map<String, dynamic>;
      expect(record1.containsKey('features'), isTrue);
      final features1 = record1['features'] as List<dynamic>;
      expect(features1.length, equals(63)); // Complete 63-dimensional feature vector

      expect(record1.containsKey('labels'), isTrue);
      final labels1 = record1['labels'] as Map<String, dynamic>;
      expect(labels1['look_again_score'], equals(1.0));
      expect(labels1['category'], equals('sys'));
      expect(labels1['urgency'], equals('critical'));

      // Privacy check: Raw text MUST NOT be exported
      expect(record1.containsKey('title'), isFalse);
      expect(record1.containsKey('content'), isFalse);
      expect(json.encode(record1).contains('Verification Code'), isFalse);
      expect(json.encode(record1).contains('Your OTP is 123456'), isFalse);

      // Parse second line (n-2)
      final record2 = json.decode(lines[1]) as Map<String, dynamic>;
      final labels2 = record2['labels'] as Map<String, dynamic>;
      expect(labels2['look_again_score'], equals(0.10));
      expect(labels2['category'], equals('promo'));
      expect(labels2['urgency'], equals('low'));
      expect(json.encode(record2).contains('Mega Sale Today'), isFalse);
    });
  });
}
