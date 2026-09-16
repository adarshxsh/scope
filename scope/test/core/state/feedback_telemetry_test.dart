import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feedback Telemetry & RLHF Logging Tests', () {
    test('recordFeedback logs sanitized training sample and exports JSONL', () async {
      final controller = NotificationController();

      final rawNotif = AppNotification(
        id: 'notif_rlhf_1',
        packageName: 'com.whatsapp',
        title: 'Security Code',
        content: 'Your verification code is 992811 sent to user@test.com',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        classifiedCategory: 'msg',
        priorityScore: 0.85,
        modelVersion: '1.0.0-tflite',
        engineVersion: '2.0.0-hybrid',
      );

      // Record positive reward signal (+1)
      await controller.recordFeedback(
        notification: rawNotif,
        rewardSignal: 1.0,
      );

      // Record negative penalty signal (-1) with correction
      await controller.recordFeedback(
        notification: rawNotif,
        rewardSignal: -1.0,
        correctedCategory: 'sys',
        correctedPriority: 'critical',
      );

      final samples = await controller.getTrainingSamples();
      expect(samples.length, equals(2));

      // Check positive reward sample (+1)
      final sample1 = samples.firstWhere((s) => s.rewardSignal == 1.0);
      expect(sample1.rewardSignal, equals(1.0));
      expect(sample1.sanitizedTitle, equals('Security Code'));
      expect(sample1.sanitizedContent, contains('[REDACTED_OTP]'));
      expect(sample1.sanitizedContent, contains('[REDACTED_EMAIL]'));
      expect(sample1.sanitizedContent, isNot(contains('992811')));

      // Check negative penalty sample (-1 with correction)
      final sample2 = samples.firstWhere((s) => s.rewardSignal == -1.0);
      expect(sample2.rewardSignal, equals(-1.0));
      expect(sample2.correctedCategory, equals('sys'));
      expect(sample2.correctedPriority, equals('critical'));


      // Test JSONL Export
      final jsonlStr = await controller.exportTrainingSamplesJsonl();
      expect(jsonlStr, isNotEmpty);

      final lines = jsonlStr.split('\n');
      expect(lines.length, equals(2));

      final jsonObjs = lines.map((l) => jsonDecode(l) as Map<String, dynamic>).toList();
      final rewardSignals = jsonObjs.map((j) => j['reward_signal']).toList();
      expect(rewardSignals, containsAll([1.0, -1.0]));
      expect(jsonObjs.first['package_name'], equals('com.whatsapp'));
      expect(jsonObjs.first['features'], isA<List>());
    });
  });
}

