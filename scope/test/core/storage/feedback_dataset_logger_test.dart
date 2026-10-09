import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/feedback_dataset_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String logFilePath;
  late FeedbackDatasetLogger logger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('feedback_logger_test');
    logFilePath = '${tempDir.path}/feedback_test.jsonl';
    logger = FeedbackDatasetLogger(
      customFilePath: logFilePath,
      maxRecords: 10,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final testNotification = AppNotification(
    id: 'test_notif_123',
    title: 'HDFC Bank Alert',
    content: 'Rs 1,200 debited for electricity bill',
    packageName: 'com.hdfc.bank',
    timestamp: 1700000000000,
    classifiedCategory: 'finance',
    priority: 'high',
    priorityScore: 0.85,
  );

  group('FeedbackDatasetLogger Tests', () {
    test('logs reward feedback into structured JSONL line', () async {
      final success = await logger.logFeedback(
        notification: testNotification,
        feedbackType: 'reward',
        userFeedback: '+1',
      );

      expect(success, isTrue);

      final count = await logger.getRecordCount();
      expect(count, equals(1));

      final records = await logger.readFeedbackRecords();
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec['id'], equals('test_notif_123'));
      expect(rec['title'], equals('HDFC Bank Alert'));
      expect(rec['content'], equals('Rs 1,200 debited for electricity bill'));
      expect(rec['packageName'], equals('com.hdfc.bank'));
      expect(rec['feedbackType'], equals('reward'));
      expect(rec['userFeedback'], equals('+1'));
      expect(rec['look_again_score'], equals(1.0));

      final features = rec['features'] as List;
      expect(features.length, equals(63));
    });

    test('logs correction feedback with custom target category and priority', () async {
      final success = await logger.logFeedback(
        notification: testNotification,
        feedbackType: 'correction',
        userFeedback: 'correction',
        targetCategory: 'work',
        targetPriority: 'critical',
      );

      expect(success, isTrue);

      final records = await logger.readFeedbackRecords();
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec['category'], equals('work'));
      expect(rec['priority'], equals('critical'));
      expect(rec['look_again_score'], equals(1.0));
      expect(rec['labels']['category_class'], equals('work'));
    });

    test('rotates logs when max record cap is exceeded', () async {
      for (int i = 0; i < 15; i++) {
        final notif = testNotification.copyWith(id: 'notif_$i');
        await logger.logFeedback(
          notification: notif,
          feedbackType: 'reward',
        );
      }

      final count = await logger.getRecordCount();
      // Cap is 10, so rotation trims down to keep newest 8 records (maxRecords * 0.8)
      expect(count, lessThanOrEqualTo(10));
    });

    test('clears logged feedback dataset', () async {
      await logger.logFeedback(
        notification: testNotification,
        feedbackType: 'penalty',
      );

      expect(await logger.getRecordCount(), equals(1));

      await logger.clearLogs();
      expect(await logger.getRecordCount(), equals(0));
    });
  });
}
