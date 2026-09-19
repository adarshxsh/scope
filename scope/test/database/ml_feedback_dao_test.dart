import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('MlFeedbackDao Unit Tests', () {
    test('insertFeedback stores entry and retrieves correctly', () async {
      final featureVector = List<double>.generate(63, (index) => index * 0.1);
      final entry = MlFeedbackTableCompanion.insert(
        notificationId: 'notif-101',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your code is 123456',
        timestamp: 1620000000,
        featureVector: jsonEncode(featureVector),
        rewardScore: 1.0,
        targetCategory: 'sys',
        targetPriority: const Value('critical'),
      );

      await db.mlFeedbackDao.insertFeedback(entry);

      final count = await db.mlFeedbackDao.getCount();
      expect(count, equals(1));

      final all = await db.mlFeedbackDao.getAll();
      expect(all.length, equals(1));
      expect(all.first.notificationId, equals('notif-101'));
      expect(all.first.rewardScore, equals(1.0));
      expect(all.first.targetCategory, equals('sys'));

      final parsedVector = jsonDecode(all.first.featureVector) as List;
      expect(parsedVector.length, equals(63));
      expect(parsedVector[1], closeTo(0.1, 0.0001));
    });

    test('insertFeedback enforces FIFO pruning cap at 10,000 records', () async {
      final sampleVector = jsonEncode(List<double>.filled(63, 1.0));

      // Batch insert 10,005 items
      await db.transaction(() async {
        for (int i = 0; i < 10005; i++) {
          await db.into(db.mlFeedbackTable).insert(
                MlFeedbackTableCompanion.insert(
                  notificationId: 'notif-$i',
                  packageName: 'com.example.app',
                  title: 'Title $i',
                  content: 'Content $i',
                  timestamp: 1000 + i,
                  featureVector: sampleVector,
                  rewardScore: 1.0,
                  targetCategory: 'general',
                ),
              );
        }
      });

      final initialCount = await db.mlFeedbackDao.getCount();
      expect(initialCount, equals(10005));

      // Trigger insertion which triggers pruning
      final triggerEntry = MlFeedbackTableCompanion.insert(
        notificationId: 'notif-latest',
        packageName: 'com.example.app',
        title: 'Latest Title',
        content: 'Latest Content',
        timestamp: 20000,
        featureVector: sampleVector,
        rewardScore: 1.0,
        targetCategory: 'general',
      );

      await db.mlFeedbackDao.insertFeedback(triggerEntry);

      final prunedCount = await db.mlFeedbackDao.getCount();
      expect(prunedCount, equals(10000));
    });
  });
}
