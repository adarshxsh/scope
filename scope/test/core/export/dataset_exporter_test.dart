import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/export/dataset_exporter.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  test('DatasetExporter exports user feedback entries to formatted JSONL file matching training schema', () async {
    final tempDir = await Directory.systemTemp.createTemp('dataset_export_test');
    final exportFile = File('${tempDir.path}/test_dataset.jsonl');

    final dummyVector = List<double>.generate(63, (index) => index * 0.1);

    final entries = [
      UserFeedbackEntry(
        id: 1,
        notificationId: 'notif-101',
        packageName: 'com.example.work',
        title: 'Meeting in 10 mins',
        content: 'Project sync with team at 4 PM.',
        rating: 1,
        feedbackType: 'reward',
        featureVector: jsonEncode(dummyVector),
        category: 'work',
        priority: 'high',
        lookAgainScore: 0.85,
        timestamp: DateTime.parse('2026-09-07T12:00:00Z'),
      ),
      UserFeedbackEntry(
        id: 2,
        notificationId: 'notif-102',
        packageName: 'com.example.shopping',
        title: '50% Off Sale',
        content: 'Use code HALF off today only!',
        rating: -1,
        feedbackType: 'penalty',
        featureVector: jsonEncode(dummyVector),
        category: 'promotional',
        priority: 'low',
        lookAgainScore: 0.15,
        timestamp: DateTime.parse('2026-09-07T12:05:00Z'),
      ),
    ];

    final createdFile = await DatasetExporter.exportToJsonl(entries, outputFile: exportFile);
    expect(createdFile.existsSync(), isTrue);

    final lines = await createdFile.readAsLines();
    expect(lines.length, equals(2));

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final json = jsonDecode(line) as Map<String, dynamic>;

      expect(json['id'], isNotNull);
      expect(json['package_name'], isNotEmpty);
      expect(json['title'], isNotNull);
      expect(json['content'], isNotNull);
      expect(json['rating'], isA<num>());
      expect(json['feedback_type'], isNotNull);

      final features = (json['features'] as List).cast<num>();
      expect(features.length, equals(63)); // Exact 63 features
      expect(features.every((val) => val.isNaN == false), isTrue); // Zero missing fields

      final labels = json['labels'] as Map<String, dynamic>;
      expect(labels['look_again_score'], isA<num>());
      expect(labels['category'], isNotNull);
      expect(labels['intent'], isNotNull);
      expect(labels['urgency'], isNotNull);
      expect(labels['requires_action'], isA<bool>());
      expect(labels['is_promotion'], isA<bool>());
      expect(labels['is_duplicate_candidate'], isA<bool>());
      expect(labels['is_recurring'], isA<bool>());
      expect(labels['look_again'], isA<bool>());
    }

    await tempDir.delete(recursive: true);
  });
}
