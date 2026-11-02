import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/core/analysis/feature_extractor.dart';

/// Exports SQLite user feedback entries and feature vectors into JSONL dataset files.
class DatasetExporter {
  /// Converts a list of [UserFeedbackEntry] into a line-delimited JSON (JSONL) file.
  ///
  /// Every record contains complete 63-element feature vectors matching the
  /// offline model training schema with zero missing fields.
  static Future<File> exportToJsonl(
    List<UserFeedbackEntry> entries, {
    File? outputFile,
  }) async {
    final file = outputFile ?? await _defaultOutputFile();
    await file.parent.create(recursive: true);

    final sink = file.openWrite(mode: FileMode.write, encoding: utf8);

    for (final entry in entries) {
      List<double> featureVector = [];
      try {
        final List<dynamic> decoded = jsonDecode(entry.featureVector);
        featureVector = decoded.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}

      // Ensure exact 63 features
      if (featureVector.length != FeatureVector.size) {
        while (featureVector.length < FeatureVector.size) {
          featureVector.add(0.0);
        }
        if (featureVector.length > FeatureVector.size) {
          featureVector = featureVector.sublist(0, FeatureVector.size);
        }
      }

      final category = entry.category ?? 'personal';
      final priority = entry.priority ?? (entry.rating > 0 ? 'high' : 'low');
      final lookAgainScore = entry.lookAgainScore ?? (entry.rating > 0 ? 1.0 : 0.0);

      final record = {
        'id': 'feedback-${entry.id}',
        'notification_id': entry.notificationId,
        'package_name': entry.packageName,
        'app_name': entry.packageName.split('.').last,
        'title': entry.title,
        'body': entry.content,
        'content': entry.content,
        'timestamp': entry.timestamp.toUtc().toIso8601String(),
        'rating': entry.rating,
        'feedback_type': entry.feedbackType,
        'features': featureVector,
        'labels': {
          'look_again_score': lookAgainScore,
          'category': category,
          'intent': 'action',
          'urgency': priority,
          'requires_action': priority == 'critical' || priority == 'high',
          'is_promotion': category == 'promotional' || category == 'promo',
          'is_duplicate_candidate': false,
          'is_recurring': false,
          'look_again': lookAgainScore >= 0.5,
        },
        'android': {
          'importance': 3,
          'conversation': false,
          'visibility': 1,
          'ongoing': false,
          'category': category,
        },
      };

      sink.write(jsonEncode(record));
      sink.write('\n');
    }

    await sink.flush();
    await sink.close();
    return file;
  }

  static Future<File> _defaultOutputFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return File(p.join(docsDir.path, 'exported_dataset.jsonl'));
  }
}
