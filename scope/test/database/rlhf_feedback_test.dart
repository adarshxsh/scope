import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('RlhfFeedbackDao Tests', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('insertFeedback records RLHF event and retrieves unsynced events', () async {
      final id1 = await db.rlhfFeedbackDao.insertFeedback(
        RlhfFeedbackEventsTableCompanion.insert(
          notificationId: const Value('notif-1'),
          featureVectorJson: '[1.0, 2.0, 3.0]',
          feedbackType: 'reward',
          rewardValue: const Value(1.0),
          originalCategory: const Value('finance'),
          originalPriority: const Value('high'),
          activeModelVersion: const Value('1.0.0-tflite'),
          timestamp: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

      final unsynced = await db.rlhfFeedbackDao.getUnsyncedFeedback();
      expect(unsynced.length, equals(1));
      expect(unsynced.first.id, equals(id1));
      expect(unsynced.first.notificationId, equals('notif-1'));
      expect(unsynced.first.feedbackType, equals('reward'));
      expect(unsynced.first.rewardValue, equals(1.0));
      expect(unsynced.first.isSynced, isFalse);
    });

    test('markAsSynced updates feedback isSynced flag', () async {
      final id1 = await db.rlhfFeedbackDao.insertFeedback(
        RlhfFeedbackEventsTableCompanion.insert(
          notificationId: const Value('notif-1'),
          featureVectorJson: '[1.0]',
          feedbackType: 'penalty',
          rewardValue: const Value(-1.0),
          isSynced: const Value(false),
        ),
      );

      final id2 = await db.rlhfFeedbackDao.insertFeedback(
        RlhfFeedbackEventsTableCompanion.insert(
          notificationId: const Value('notif-2'),
          featureVectorJson: '[2.0]',
          feedbackType: 'correction',
          correctedCategory: const Value('sys'),
          correctedPriority: const Value('critical'),
          isSynced: const Value(false),
        ),
      );

      var unsynced = await db.rlhfFeedbackDao.getUnsyncedFeedback();
      expect(unsynced.length, equals(2));

      await db.rlhfFeedbackDao.markAsSynced([id1]);

      unsynced = await db.rlhfFeedbackDao.getUnsyncedFeedback();
      expect(unsynced.length, equals(1));
      expect(unsynced.first.id, equals(id2));

      final all = await db.rlhfFeedbackDao.getAllFeedback();
      expect(all.length, equals(2));
      expect(all.firstWhere((e) => e.id == id1).isSynced, isTrue);
    });
  });
}
