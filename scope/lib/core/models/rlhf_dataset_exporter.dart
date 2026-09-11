import 'dart:convert';
import 'dart:io';
import 'package:scope/database/attention_database.dart';

/// Utility to export logged RLHF feedback entries from Drift database into JSONL format
/// compatible with the AttentionOS machine learning training pipeline.
class RlhfDatasetExporter {
  /// Converts a single RlhfFeedbackEntry into a JSON-encodable map for AttentionOS retraining.
  static Map<String, dynamic> entryToMap(RlhfFeedbackEntry entry) {
    List<double> vector = [];
    try {
      final decoded = jsonDecode(entry.featureVector);
      if (decoded is List) {
        vector = decoded.map((e) => (e as num).toDouble()).toList();
      }
    } catch (_) {
      vector = List<double>.filled(63, 0.0);
    }

    return {
      'notification_id': entry.notificationId,
      'feature_vector': vector,
      'predicted_score': entry.predictedScore ?? 0.0,
      'reward': entry.rewardScore,
      'corrected_category': entry.updatedCategory,
      'corrected_priority': entry.updatedPriority,
      'timestamp': entry.timestamp.toIso8601String(),
    };
  }

  /// Converts a list of RlhfFeedbackEntry records into JSONL format string.
  static String exportToJsonl(List<RlhfFeedbackEntry> entries) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      final map = entryToMap(entry);
      buffer.writeln(jsonEncode(map));
    }
    return buffer.toString();
  }

  /// Writes RlhfFeedbackEntry records to a specified file in JSONL format.
  static Future<File> exportToFile(List<RlhfFeedbackEntry> entries, File targetFile) async {
    final jsonlContent = exportToJsonl(entries);
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }
    return await targetFile.writeAsString(jsonlContent, flush: true);
  }
}
