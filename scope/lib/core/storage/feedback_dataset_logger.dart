import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/models/notification_model.dart';

/// Persists structured user feedback (rewards, penalties, category/priority corrections)
/// and extracted 63-dimensional feature vectors to local JSONL dataset storage.
class FeedbackDatasetLogger {
  static FeedbackDatasetLogger? _instance;
  final String? customFilePath;
  final int maxRecords;
  final int maxSizeBytes;

  static const String defaultFileName = 'feedback_dataset.jsonl';
  static const int defaultMaxRecords = 50000;
  static const int defaultMaxSizeBytes = 50 * 1024 * 1024; // 50 MB

  FeedbackDatasetLogger({
    this.customFilePath,
    this.maxRecords = defaultMaxRecords,
    this.maxSizeBytes = defaultMaxSizeBytes,
  });

  static FeedbackDatasetLogger get instance => _instance ??= FeedbackDatasetLogger();

  /// Returns the target file for logging JSONL feedback.
  Future<File?> getLogFile() async {
    try {
      if (customFilePath != null) {
        final file = File(customFilePath!);
        await file.parent.create(recursive: true);
        return file;
      }

      final docDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(docDir.path, defaultFileName));
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      return file;
    } catch (e) {
      debugPrint('FeedbackDatasetLogger: Failed to resolve log file path: $e');
      return null;
    }
  }

  /// Appends a user feedback interaction to local JSONL dataset storage.
  Future<bool> logFeedback({
    required AppNotification notification,
    required String feedbackType, // 'reward', 'penalty', or 'correction'
    String? userFeedback, // '+1', '-1', etc.
    String? targetCategory,
    String? targetPriority,
    double? targetScore,
  }) async {
    try {
      final file = await getLogFile();
      if (file == null) return false;

      // Ensure 63-dimensional feature vector is extracted
      final List<double> features = FeatureExtractor.extractFromAppNotification(notification);

      // Determine target category, priority, and look_again_score
      final category = targetCategory ?? notification.classifiedCategory ?? 'msg';
      final priority = targetPriority ?? notification.priority ?? 'medium';

      double resolvedScore = targetScore ?? notification.priorityScore ?? 0.5;
      if (targetScore == null) {
        if (feedbackType == 'reward') {
          resolvedScore = 1.0;
        } else if (feedbackType == 'penalty') {
          resolvedScore = 0.0;
        } else if (feedbackType == 'correction') {
          switch (priority.toLowerCase()) {
            case 'critical':
              resolvedScore = 1.0;
              break;
            case 'high':
              resolvedScore = 0.85;
              break;
            case 'medium':
              resolvedScore = 0.50;
              break;
            case 'low':
            default:
              resolvedScore = 0.15;
              break;
          }
        }
      }

      final record = <String, dynamic>{
        'id': notification.id,
        'timestamp': notification.timestamp,
        'title': notification.title,
        'content': notification.content,
        'packageName': notification.packageName,
        'feedbackType': feedbackType,
        'userFeedback': userFeedback ?? (feedbackType == 'reward' ? '+1' : (feedbackType == 'penalty' ? '-1' : 'correction')),
        'category': category,
        'priority': priority,
        'look_again_score': resolvedScore,
        'features': features,
        'labels': <String, dynamic>{
          'category_class': category,
          'urgency': priority,
          'look_again_score': resolvedScore,
        },
      };

      final jsonLine = '${jsonEncode(record)}\n';
      await file.writeAsString(jsonLine, mode: FileMode.append, flush: true);

      // Perform rotation check if storage threshold exceeded
      await _rotateIfNeeded(file);

      debugPrint('FeedbackDatasetLogger: Successfully persisted feedback record (type: $feedbackType).');
      return true;
    } catch (e) {
      debugPrint('FeedbackDatasetLogger: Failed to log feedback: $e');
      return false;
    }
  }

  /// Reads all valid feedback records from local JSONL storage.
  Future<List<Map<String, dynamic>>> readFeedbackRecords() async {
    final records = <Map<String, dynamic>>[];
    try {
      final file = await getLogFile();
      if (file == null || !await file.exists()) return records;

      final lines = await file.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) {
            records.add(decoded);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('FeedbackDatasetLogger: Failed to read feedback records: $e');
    }
    return records;
  }

  /// Returns total count of logged records in storage.
  Future<int> getRecordCount() async {
    final records = await readFeedbackRecords();
    return records.length;
  }

  /// Returns total file size in bytes.
  Future<int> getFileSizeBytes() async {
    try {
      final file = await getLogFile();
      if (file == null || !await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  /// Clears all logged feedback records.
  Future<void> clearLogs() async {
    try {
      final file = await getLogFile();
      if (file != null && await file.exists()) {
        await file.writeAsString('');
      }
    } catch (e) {
      debugPrint('FeedbackDatasetLogger: Failed to clear logs: $e');
    }
  }

  /// Rotates log file keeping newest entries if line count or file size exceeds limits.
  Future<void> _rotateIfNeeded(File file) async {
    try {
      final length = await file.length();
      final lines = await file.readAsLines();

      if (lines.length > maxRecords || length > maxSizeBytes) {
        final keepCount = (maxRecords * 0.8).toInt();
        final trimmedLines = lines.skip(lines.length > keepCount ? lines.length - keepCount : 0).toList();
        final newContent = '${trimmedLines.join('\n')}\n';
        await file.writeAsString(newContent, flush: true);
        debugPrint('FeedbackDatasetLogger: Rotated logs from ${lines.length} to ${trimmedLines.length} records.');
      }
    } catch (e) {
      debugPrint('FeedbackDatasetLogger: Rotation failed: $e');
    }
  }
}
