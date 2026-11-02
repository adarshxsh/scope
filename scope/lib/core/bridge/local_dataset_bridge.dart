import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/models/notification_model.dart';

/// Represents a recorded user interaction feedback entry for a notification.
class UserFeedbackRecord {
  final String notificationId;
  final String feedbackAction; // 'reward' (+1), 'penalty' (-1), 'reviewed', 'archived', 'dismissed'
  final double? customTargetScore;
  final DateTime timestamp;

  UserFeedbackRecord({
    required this.notificationId,
    required this.feedbackAction,
    this.customTargetScore,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'notificationId': notificationId,
        'feedbackAction': feedbackAction,
        'customTargetScore': customTargetScore,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory UserFeedbackRecord.fromMap(Map<String, dynamic> map) => UserFeedbackRecord(
        notificationId: map['notificationId'] as String? ?? '',
        feedbackAction: map['feedbackAction'] as String? ?? 'none',
        customTargetScore: (map['customTargetScore'] as num?)?.toDouble(),
        timestamp: map['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
            : null,
      );
}

/// Service bridging local storage notification logs and feedback entries into
/// structured JSONL training datasets for offline model retraining.
class LocalDatasetBridge {
  static LocalDatasetBridge? _instance;
  final Map<String, UserFeedbackRecord> _feedbackStore = {};
  bool _feedbackLoaded = false;

  LocalDatasetBridge._();

  static LocalDatasetBridge get instance => _instance ??= LocalDatasetBridge._();

  /// Returns unmodifiable map of recorded feedback.
  Map<String, UserFeedbackRecord> get feedbackStore => Map.unmodifiable(_feedbackStore);

  /// Loads recorded user feedback entries from local app storage.
  Future<void> loadFeedback() async {
    if (_feedbackLoaded) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/user_feedback.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = json.decode(jsonStr) as List<dynamic>;
        for (final item in list) {
          final record = UserFeedbackRecord.fromMap(Map<String, dynamic>.from(item as Map));
          _feedbackStore[record.notificationId] = record;
        }
      }
    } catch (e) {
      debugPrint('LocalDatasetBridge: Error loading user feedback: $e');
    } finally {
      _feedbackLoaded = true;
    }
  }

  /// Records user feedback interaction (reward +1, penalty -1, or queue action).
  Future<void> recordFeedback({
    required String notificationId,
    required String action,
    double? customTargetScore,
  }) async {
    await loadFeedback();
    final record = UserFeedbackRecord(
      notificationId: notificationId,
      feedbackAction: action,
      customTargetScore: customTargetScore,
    );
    _feedbackStore[notificationId] = record;
    await _persistFeedback();
  }

  /// Persists feedback store to local app storage.
  Future<void> _persistFeedback() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/user_feedback.json');
      final list = _feedbackStore.values.map((r) => r.toMap()).toList();
      await file.writeAsString(json.encode(list));
    } catch (e) {
      debugPrint('LocalDatasetBridge: Error saving user feedback: $e');
    }
  }

  /// Exports notification feature vectors, priority scores, and user feedback into a structured JSONL file.
  /// Omits raw notification text (title/content) to maintain on-device privacy.
  Future<File> exportTrainingDataset({
    required List<AppNotification> notifications,
    String? outputPath,
  }) async {
    await loadFeedback();

    File targetFile;
    if (outputPath != null && outputPath.isNotEmpty) {
      targetFile = File(outputPath);
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      final datasetDir = Directory('${docDir.path}/datasets');
      if (!datasetDir.existsSync()) {
        datasetDir.createSync(recursive: true);
      }
      targetFile = File('${datasetDir.path}/training_dataset_${DateTime.now().millisecondsSinceEpoch}.jsonl');
    }

    if (!targetFile.parent.existsSync()) {
      targetFile.parent.createSync(recursive: true);
    }

    final sink = targetFile.openWrite(mode: FileMode.write, encoding: utf8);

    for (final notif in notifications) {
      final feedback = _feedbackStore[notif.id];
      final feedbackAction = feedback?.feedbackAction ?? 'none';

      // Feature vector (63 numerical dimensions)
      final featureVector = FeatureExtractor.extractFromAppNotification(notif);

      // Determine target score based on user feedback or model review score
      double targetScore = notif.priorityScore ?? 0.5;
      if (feedback != null) {
        if (feedback.customTargetScore != null) {
          targetScore = feedback.customTargetScore!;
        } else if (feedback.feedbackAction == 'reward') {
          targetScore = 1.0;
        } else if (feedback.feedbackAction == 'penalty') {
          targetScore = 0.0;
        }
      }
      targetScore = targetScore.clamp(0.0, 1.0);

      final category = (notif.classifiedCategory ?? notif.category ?? 'msg').isEmpty
          ? 'msg'
          : (notif.classifiedCategory ?? notif.category ?? 'msg');
      final urgency = (notif.priority ?? 'medium').isEmpty ? 'medium' : (notif.priority ?? 'medium');

      final requiresAction = featureVector[44] == 1.0;
      final isPromotion = featureVector[20] == 1.0;
      final isDuplicateCandidate = featureVector[47] == 1.0;
      final isRecurring = featureVector[45] == 1.0;
      final lookAgain = targetScore >= 0.5;

      // JSONL Record Format matching offline AttentionOS training pipeline
      // Strictly OMIT raw notification title and content for privacy.
      final record = {
        'features': featureVector,
        'category': category,
        'intent': 'action',
        'urgency': urgency,
        'labels': {
          'category': category,
          'category_class': category,
          'intent': 'action',
          'urgency': urgency,
          'requires_action': requiresAction,
          'is_promotion': isPromotion,
          'is_duplicate_candidate': isDuplicateCandidate,
          'is_recurring': isRecurring,
          'look_again': lookAgain,
          'look_again_score': targetScore,
        },
        'look_again_score': targetScore,
        'feedback_action': feedbackAction,
        'model_version': notif.modelVersion ?? 'unknown',
        'timestamp': notif.timestamp,
      };

      sink.write(json.encode(record));
      sink.write('\n');
    }

    await sink.flush();
    await sink.close();

    debugPrint('LocalDatasetBridge: Successfully exported ${notifications.length} records to ${targetFile.path}');
    return targetFile;
  }

  /// Clears in-memory and stored feedback (for unit testing).
  void clearFeedback() {
    _feedbackStore.clear();
    _feedbackLoaded = false;
  }
}
