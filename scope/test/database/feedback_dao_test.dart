import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:scope/database/attention_database.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/feature_extractor.dart';

void main() {
  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('User reward and penalty actions write 63-feature vectors to SQLite database', () async {
    final notif = AppNotification(
      id: 'test-notif-1',
      packageName: 'com.bank.app',
      title: 'Salary Credited',
      content: 'Your account 1234 was credited with Rs 50,000 on 24 Jun.',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final vector = FeatureExtractor.extractFromAppNotification(notif);
    expect(vector.length, equals(63));

    // Record Reward (+1)
    await db.userFeedbackDao.insertFeedback(UserFeedbackTableCompanion.insert(
      notificationId: notif.id,
      packageName: notif.packageName,
      title: notif.title,
      content: notif.content,
      rating: 1,
      feedbackType: 'reward',
      featureVector: jsonEncode(vector),
      category: const drift.Value('finance'),
      priority: const drift.Value('high'),
      lookAgainScore: const drift.Value(1.0),
    ));

    // Record Penalty (-1) with correction
    await db.userFeedbackDao.insertFeedback(UserFeedbackTableCompanion.insert(
      notificationId: notif.id,
      packageName: notif.packageName,
      title: notif.title,
      content: notif.content,
      rating: -1,
      feedbackType: 'penalty',
      featureVector: jsonEncode(vector),
      category: const drift.Value('promotional'),
      priority: const drift.Value('low'),
      lookAgainScore: const drift.Value(0.15),
    ));

    final allFeedback = await db.userFeedbackDao.getAll();
    expect(allFeedback.length, equals(2));

    // Verify Reward entry
    final rewardEntry = allFeedback.firstWhere((e) => e.rating == 1);
    expect(rewardEntry.feedbackType, equals('reward'));
    final rewardVector = (jsonDecode(rewardEntry.featureVector) as List).cast<num>();
    expect(rewardVector.length, equals(63));
    expect(rewardVector[10], equals(1.0)); // contains_money

    // Verify Penalty entry
    final penaltyEntry = allFeedback.firstWhere((e) => e.rating == -1);
    expect(penaltyEntry.feedbackType, equals('penalty'));
    expect(penaltyEntry.category, equals('promotional'));
    expect(penaltyEntry.priority, equals('low'));
    final penaltyVector = (jsonDecode(penaltyEntry.featureVector) as List).cast<num>();
    expect(penaltyVector.length, equals(63));
  });
}
