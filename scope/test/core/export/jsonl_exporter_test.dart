import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/export/jsonl_exporter.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('JsonlExporter Unit Tests', () {
    test('toDatasetRecord exports 63-dimensional feature vector and target labels', () {
      final notif = AppNotification(
        id: 'test-feedback-1',
        packageName: 'com.whatsapp',
        title: 'OTP Code',
        content: 'Your verification code is 883102. Valid for 10 minutes.',
        timestamp: 1700000000000,
        userRating: 1,
        targetLabel: 'critical',
        priority: 'critical',
        priorityScore: 100.0,
        classifiedCategory: 'otp',
      );

      final record = JsonlExporter.toDatasetRecord(notif);

      expect(record['id'], equals('test-feedback-1'));
      expect(record['package_name'], equals('com.whatsapp'));
      expect(record['user_rating'], equals(1));
      expect(record['target_label'], equals('critical'));
      expect(record['look_again_score'], equals(100.0));

      final features = record['features'] as List<double>;
      expect(features.length, equals(63));
      for (final val in features) {
        expect(val.isNaN, isFalse);
        expect(val.isInfinite, isFalse);
      }

      final labels = record['labels'] as Map<String, dynamic>;
      expect(labels['category_class'], equals('otp'));
      expect(labels['urgency'], equals('critical'));
      expect(labels['look_again_score'], equals(100.0));
      expect(labels['look_again'], isTrue);
    });

    test('exportToJsonl writes valid JSONL feedback records to file', () async {
      final notifs = [
        AppNotification(
          id: 'n1',
          packageName: 'com.whatsapp',
          title: 'Hello',
          content: 'How are you?',
          timestamp: 1700000000000,
          userRating: 1,
          targetLabel: 'medium',
        ),
        AppNotification(
          id: 'n2',
          packageName: 'com.amazon',
          title: 'Discount',
          content: '50% off today!',
          timestamp: 1700000001000,
          userRating: -1,
          targetLabel: 'low',
        ),
      ];

      final tempDir = await Directory.systemTemp.createTemp('jsonl_export_test');
      final exportPath = '${tempDir.path}/test_export.jsonl';

      final file = await JsonlExporter.exportToJsonl(notifs, outputPath: exportPath);
      expect(await file.exists(), isTrue);

      final lines = await file.readAsLines();
      expect(lines.length, equals(2));

      final firstJson = json.decode(lines[0]) as Map<String, dynamic>;
      expect(firstJson['id'], equals('n1'));
      expect((firstJson['features'] as List).length, equals(63));
      expect(firstJson['user_rating'], equals(1));
      expect(firstJson['target_label'], equals('medium'));

      final secondJson = json.decode(lines[1]) as Map<String, dynamic>;
      expect(secondJson['id'], equals('n2'));
      expect((secondJson['features'] as List).length, equals(63));
      expect(secondJson['user_rating'], equals(-1));
      expect(secondJson['target_label'], equals('low'));

      await tempDir.delete(recursive: true);
    });
  });
}
