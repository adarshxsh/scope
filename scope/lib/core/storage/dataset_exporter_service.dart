import 'dart:convert';
import 'dart:io';
import 'package:scope/database/attention_database.dart';

/// Service to export local RLHF feedback entries into standardized JSONL files for offline Python training.
class DatasetExporterService {
  final AttentionDatabase db;

  DatasetExporterService(this.db);

  /// Converts a list of feedback entries into a JSONL string.
  String formatEntriesToJsonl(List<MlFeedbackEntry> entries) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      final record = mapEntryToRecord(entry);
      buffer.writeln(jsonEncode(record));
    }
    return buffer.toString();
  }

  /// Exports all feedback entries stored in the database to a JSONL file.
  Future<File> exportToJsonlFile(File destinationFile) async {
    final entries = await db.mlFeedbackDao.getAll();
    final jsonlStr = formatEntriesToJsonl(entries);
    if (!destinationFile.parent.existsSync()) {
      destinationFile.parent.createSync(recursive: true);
    }
    return destinationFile.writeAsString(jsonlStr, flush: true);
  }

  /// Maps a single MlFeedbackEntry into a JSON map matching offline training schema.
  Map<String, dynamic> mapEntryToRecord(MlFeedbackEntry entry) {
    List<double> featureVector = [];
    try {
      final parsed = jsonDecode(entry.featureVector);
      if (parsed is List) {
        featureVector = parsed.map((e) => (e as num).toDouble()).toList();
      }
    } catch (_) {
      featureVector = List<double>.filled(63, 0.0);
    }

    final category = entry.targetCategory.isNotEmpty ? entry.targetCategory : 'financial';
    final priority = (entry.targetPriority != null && entry.targetPriority!.isNotEmpty)
        ? entry.targetPriority!
        : 'medium';

    final targetScore = _priorityToScore(priority, entry.rewardScore);

    return {
      'id': entry.notificationId,
      'packageName': entry.packageName,
      'title': entry.title,
      'timestamp': entry.timestamp,
      'features': featureVector,
      'reward_score': entry.rewardScore,
      'target_category': category,
      'target_priority': priority,
      'look_again_score': targetScore,
      'category': category,
      'intent': 'action',
      'urgency': priority,
      'requires_action': false,
      'is_promotion': category == 'promotional' || category == 'promo',
      'is_duplicate_candidate': false,
      'is_recurring': false,
      'look_again': entry.rewardScore > 0,
      'labels': {
        'category_class': category,
        'intent': 'action',
        'urgency': priority,
        'requires_action': false,
        'is_promotion': category == 'promotional' || category == 'promo',
        'is_duplicate_candidate': false,
        'is_recurring': false,
        'look_again': entry.rewardScore > 0,
        'look_again_score': targetScore,
      },
    };
  }

  double _priorityToScore(String priority, double rewardScore) {
    double baseScore;
    switch (priority.toLowerCase()) {
      case 'critical':
        baseScore = 100.0;
        break;
      case 'high':
        baseScore = 80.0;
        break;
      case 'medium':
        baseScore = 50.0;
        break;
      case 'low':
      default:
        baseScore = 15.0;
        break;
    }

    // Apply minor nudge if reward or penalty
    if (rewardScore < 0) {
      // Penalty: shift slightly lower if reward is negative
      baseScore = (baseScore - 10.0).clamp(0.0, 100.0);
    }
    return baseScore;
  }
}
