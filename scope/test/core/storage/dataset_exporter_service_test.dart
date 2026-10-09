import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/core/storage/dataset_exporter_service.dart';

void main() {
  late AttentionDatabase db;
  late DatasetExporterService exporter;

  setUp(() {
    db = AttentionDatabase.inMemory();
    exporter = DatasetExporterService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DatasetExporterService Unit Tests', () {
    test('mapEntryToRecord formats feedback entry with 63 features and python-compatible schema', () {
      final features = List<double>.generate(63, (i) => i * 0.5);
      final entry = MlFeedbackEntry(
        id: 1,
        notificationId: 'notif-xyz',
        packageName: 'com.bank.app',
        title: 'Debit Notice',
        content: 'Spent \$50',
        timestamp: 1600000000,
        featureVector: jsonEncode(features),
        rewardScore: 1.0,
        targetCategory: 'finance',
        targetPriority: 'high',
        createdAt: DateTime.now(),
      );

      final record = exporter.mapEntryToRecord(entry);

      expect(record['id'], equals('notif-xyz'));
      expect(record['packageName'], equals('com.bank.app'));
      expect(record['reward_score'], equals(1.0));
      expect(record['target_category'], equals('finance'));
      expect(record['target_priority'], equals('high'));
      expect((record['features'] as List).length, equals(63));
      expect(record['labels'], isA<Map<String, dynamic>>());
      expect(record['labels']['category_class'], equals('finance'));
    });

    test('formatEntriesToJsonl generates valid JSONL lines', () {
      final features = List<double>.filled(63, 0.0);
      final entries = [
        MlFeedbackEntry(
          id: 1,
          notificationId: '1',
          packageName: 'com.a',
          title: 'A',
          content: 'A content',
          timestamp: 100,
          featureVector: jsonEncode(features),
          rewardScore: 1.0,
          targetCategory: 'sys',
          targetPriority: 'critical',
          createdAt: DateTime.now(),
        ),
        MlFeedbackEntry(
          id: 2,
          notificationId: '2',
          packageName: 'com.b',
          title: 'B',
          content: 'B content',
          timestamp: 200,
          featureVector: jsonEncode(features),
          rewardScore: -1.0,
          targetCategory: 'promo',
          targetPriority: 'low',
          createdAt: DateTime.now(),
        ),
      ];

      final jsonl = exporter.formatEntriesToJsonl(entries);
      final lines = jsonl.trim().split('\n');

      expect(lines.length, equals(2));

      final obj1 = jsonDecode(lines[0]);
      expect(obj1['id'], equals('1'));
      expect(obj1['reward_score'], equals(1.0));

      final obj2 = jsonDecode(lines[1]);
      expect(obj2['id'], equals('2'));
      expect(obj2['reward_score'], equals(-1.0));
    });
  });
}
