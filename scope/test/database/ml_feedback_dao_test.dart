import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('MlFeedbackDao Database Tests', () {
    test('insertFeedback and getAll execute with schema constraints', () async {
      final entry = MlFeedbackEntry(
        id: 0,
        notificationId: 'notif_db_1',
        packageName: 'com.whatsapp',
        title: 'New message',
        content: 'Meeting at 3pm',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        featureVector: '[0.0, 1.0, 0.5]',
        rewardScore: 1.0,
        targetCategory: 'msg',
        targetPriority: 'high',
        createdAt: DateTime.now(),
      );

      await db.mlFeedbackDao.insertFeedback(entry);

      final records = await db.mlFeedbackDao.getAll();
      expect(records.length, equals(1));
      expect(records[0].notificationId, equals('notif_db_1'));
      expect(records[0].targetCategory, equals('msg'));
      expect(records[0].rewardScore, equals(1.0));

      final count = await db.mlFeedbackDao.getCount();
      expect(count, equals(1));
    });

    test('clearAll removes all feedback entries', () async {
      final entry = MlFeedbackEntry(
        id: 0,
        notificationId: 'notif_db_2',
        packageName: 'com.google.android.gm',
        title: 'Urgent email',
        content: 'Action required',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        featureVector: '[0.1, 0.2]',
        rewardScore: -1.0,
        targetCategory: 'msg',
        createdAt: DateTime.now(),
      );

      await db.mlFeedbackDao.insertFeedback(entry);
      await db.mlFeedbackDao.clearAll();

      final count = await db.mlFeedbackDao.getCount();
      expect(count, equals(0));
    });
  });
}
