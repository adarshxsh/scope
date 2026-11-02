import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/feedback_dataset_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File customFile;
  late FeedbackDatasetLogger logger;

  final sampleNotif = AppNotification(
    id: 'test_notif_101',
    packageName: 'com.hdfcbank.pay',
    title: 'Debit Alert',
    content: 'Rs. 4,500 debited from account xx1234',
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('feedback_logger_test_');
    customFile = File('${tempDir.path}/feedback_test.jsonl');
    logger = FeedbackDatasetLogger(
      customFilePath: customFile.path,
      maxRecords: 5,
      maxSizeBytes: 1024 * 1024,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FeedbackDatasetLogger Unit Tests', () {
    test('logFeedback appends formatted JSONL entry', () async {
      final success = await logger.logFeedback(
        notification: sampleNotif,
        feedbackType: 'reward',
        userFeedback: '+1',
        targetCategory: 'finance',
        targetPriority: 'high',
      );

      expect(success, isTrue);
      expect(await customFile.exists(), isTrue);

      final records = await logger.readFeedbackRecords();
      expect(records.length, equals(1));
      expect(records[0]['id'], equals('test_notif_101'));
      expect(records[0]['feedbackType'], equals('reward'));
      expect(records[0]['category'], equals('finance'));
      expect(records[0]['features'], isA<List>());
      expect((records[0]['features'] as List).length, equals(63));
    });

    test('getRecordCount and clearLogs operate correctly', () async {
      await logger.logFeedback(notification: sampleNotif, feedbackType: 'reward');
      await logger.logFeedback(notification: sampleNotif, feedbackType: 'penalty');

      final count = await logger.getRecordCount();
      expect(count, equals(2));

      await logger.clearLogs();
      final countAfterClear = await logger.getRecordCount();
      expect(countAfterClear, equals(0));
    });

    test('Rotation trims records when maxRecords threshold exceeded', () async {
      for (int i = 0; i < 10; i++) {
        await logger.logFeedback(
          notification: sampleNotif,
          feedbackType: 'reward',
          targetScore: i.toDouble(),
        );
      }

      final records = await logger.readFeedbackRecords();
      // maxRecords is set to 5, so keepCount should be 4
      expect(records.length, lessThanOrEqualTo(5));
    });
  });
}
