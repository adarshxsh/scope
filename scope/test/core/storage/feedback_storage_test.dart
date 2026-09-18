import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';

void main() {
  group('Feedback Storage Tests', () {
    test('InMemoryNotificationStorage saves and retrieves feedback logs', () async {
      final storage = InMemoryNotificationStorage();

      await storage.saveFeedback(
        notificationId: 'notif-1',
        feedbackType: 'reward',
        originalPriority: 'low',
        originalCategory: 'promotional',
      );

      await storage.saveFeedback(
        notificationId: 'notif-2',
        feedbackType: 'penalty',
        originalPriority: 'high',
        correctedPriority: 'low',
        originalCategory: 'financial',
        correctedCategory: 'promotional',
      );

      final logs = await storage.getFeedbackLogs();
      expect(logs.length, equals(2));

      expect(logs[0]['notificationId'], equals('notif-1'));
      expect(logs[0]['feedbackType'], equals('reward'));
      expect(logs[0]['originalPriority'], equals('low'));

      expect(logs[1]['notificationId'], equals('notif-2'));
      expect(logs[1]['feedbackType'], equals('penalty'));
      expect(logs[1]['correctedPriority'], equals('low'));
      expect(logs[1]['correctedCategory'], equals('promotional'));
    });

    test('DriftNotificationStorage persists feedback logs in SQLite DB', () async {
      final db = AttentionDatabase.inMemory();
      final storage = DriftNotificationStorage(db);

      await storage.saveFeedback(
        notificationId: 'drift-notif-1',
        feedbackType: 'reward',
        originalPriority: 'medium',
        originalCategory: 'work',
      );

      await storage.saveFeedback(
        notificationId: 'drift-notif-2',
        feedbackType: 'penalty',
        originalPriority: 'low',
        correctedPriority: 'critical',
        originalCategory: 'system',
        correctedCategory: 'financial',
      );

      final logs = await storage.getFeedbackLogs();
      expect(logs.length, equals(2));

      expect(logs[0]['notificationId'], equals('drift-notif-1'));
      expect(logs[0]['feedbackType'], equals('reward'));

      expect(logs[1]['notificationId'], equals('drift-notif-2'));
      expect(logs[1]['feedbackType'], equals('penalty'));
      expect(logs[1]['correctedPriority'], equals('critical'));

      await db.close();
    });
  });
}
