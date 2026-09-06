import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/models/notification_model.dart';

/// Exports stored notification feedback records into local JSONL files
/// matching the feature extraction and offline training dataset schema.
class JsonlExporter {
  /// Maps priority string to numerical look_again_score (0.0 to 100.0).
  static double priorityToScore(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'critical':
        return 100.0;
      case 'high':
        return 80.0;
      case 'medium':
        return 35.0;
      case 'low':
        return 0.0;
      default:
        return 35.0;
    }
  }

  /// Converts an [AppNotification] feedback record to a Map JSON record.
  static Map<String, dynamic> toDatasetRecord(AppNotification notification) {
    // 1. Extract 63-dimensional feature vector
    final featureVector = FeatureExtractor.extractFromAppNotification(notification);

    final targetLabel = notification.targetLabel ?? notification.priority ?? 'medium';

    // 2. Resolve target score (look_again_score)
    final double lookAgainScore;
    if (notification.targetLabel != null) {
      final parsed = double.tryParse(notification.targetLabel!);
      if (parsed != null) {
        lookAgainScore = parsed;
      } else {
        lookAgainScore = priorityToScore(notification.targetLabel);
      }
    } else {
      lookAgainScore = notification.priorityScore ?? priorityToScore(notification.priority);
    }

    final categoryClass = (notification.classifiedCategory ?? notification.category ?? 'general').trim();
    final nonNullCategory = categoryClass.isEmpty ? 'general' : categoryClass;
    final nonNullUrgency = targetLabel.trim().isEmpty ? 'medium' : targetLabel;

    return {
      'id': notification.id,
      'package_name': notification.packageName,
      'title': notification.title,
      'content': notification.content,
      'timestamp': notification.timestamp,
      'user_rating': notification.userRating,
      'target_label': targetLabel,
      'look_again_score': lookAgainScore,
      'features': featureVector,
      'labels': {
        'category_class': nonNullCategory,
        'intent': 'general',
        'urgency': nonNullUrgency,
        'requires_action': false,
        'is_promotion': nonNullUrgency == 'low' || nonNullCategory.contains('promo'),
        'is_duplicate_candidate': false,
        'is_recurring': false,
        'look_again': lookAgainScore >= 50.0,
        'look_again_score': lookAgainScore,
      },
    };
  }

  /// Exports feedback records to a local JSONL file.
  /// If [outputPath] is not specified, defaults to `${documentsDir}/feedback_export.jsonl`.
  static Future<File> exportToJsonl(
    List<AppNotification> notifications, {
    String? outputPath,
  }) async {
    final String targetPath;
    if (outputPath != null) {
      targetPath = outputPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      targetPath = '${docsDir.path}/feedback_export.jsonl';
    }

    final file = File(targetPath);
    await file.parent.create(recursive: true);

    final sink = file.openWrite(mode: FileMode.write, encoding: utf8);
    for (final notification in notifications) {
      final record = toDatasetRecord(notification);
      sink.write(json.encode(record));
      sink.write('\n');
    }
    await sink.flush();
    await sink.close();

    return file;
  }
}
