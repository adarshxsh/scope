import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/rlhf_dataset_exporter.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase database;

  setUp(() {
    database = AttentionDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  test('RlhfFeedbackDao inserts and retrieves feedback entries', () async {
    final featureVector = List<double>.generate(63, (i) => i * 0.1);
    final jsonVector = jsonEncode(featureVector);

    await database.rlhfFeedbackDao.insertFeedback(
      RlhfFeedbackTableCompanion.insert(
        notificationId: 'notif_123',
        featureVector: jsonVector,
        predictedScore: const Value(0.85),
        rewardScore: 1.0,
        updatedCategory: const Value('finance'),
        updatedPriority: const Value('critical'),
      ),
    );

    final count = await database.rlhfFeedbackDao.getCount();
    expect(count, equals(1));

    final entries = await database.rlhfFeedbackDao.getAll();
    expect(entries.length, equals(1));
    expect(entries.first.notificationId, equals('notif_123'));
    expect(entries.first.rewardScore, equals(1.0));
    expect(entries.first.updatedCategory, equals('finance'));
    expect(entries.first.updatedPriority, equals('critical'));
  });

  test('RlhfFeedbackDao prunes entries when count exceeds 5000 max cap', () async {
    final featureVector = jsonEncode(List<double>.filled(63, 0.0));

    // Insert 50 entries and verify custom max threshold
    final baseTime = DateTime.now();
    for (int i = 0; i < 50; i++) {
      await database.rlhfFeedbackDao.insertFeedback(
        RlhfFeedbackTableCompanion.insert(
          notificationId: 'notif_$i',
          featureVector: featureVector,
          rewardScore: 1.0,
          timestamp: Value(baseTime.add(Duration(seconds: i))),
        ),
      );
    }

    expect(await database.rlhfFeedbackDao.getCount(), equals(50));

    // Prune to max 30 entries
    await database.rlhfFeedbackDao.pruneExcessEntries(30);
    expect(await database.rlhfFeedbackDao.getCount(), equals(30));

    // Ensure oldest entries were deleted (newest remaining)
    final entries = await database.rlhfFeedbackDao.getAll();
    expect(entries.length, equals(30));
    expect(entries.first.notificationId, equals('notif_49'));
  });

  test('RlhfDatasetExporter converts feedback entries into valid JSONL format', () async {
    final featureVector = List<double>.filled(63, 1.0);
    final jsonVector = jsonEncode(featureVector);

    await database.rlhfFeedbackDao.insertFeedback(
      RlhfFeedbackTableCompanion.insert(
        notificationId: 'export_notif_1',
        featureVector: jsonVector,
        predictedScore: const Value(0.75),
        rewardScore: -1.0,
        updatedCategory: const Value('promo'),
        updatedPriority: const Value('low'),
      ),
    );

    final entries = await database.rlhfFeedbackDao.getAll();
    final jsonlOutput = RlhfDatasetExporter.exportToJsonl(entries);

    final lines = jsonlOutput.trim().split('\n');
    expect(lines.length, equals(1));

    final parsed = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(parsed['notification_id'], equals('export_notif_1'));
    expect(parsed['reward'], equals(-1.0));
    expect(parsed['corrected_category'], equals('promo'));
    expect(parsed['corrected_priority'], equals('low'));
    expect((parsed['feature_vector'] as List).length, equals(63));
  });
}
