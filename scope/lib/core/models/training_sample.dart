/// Represents a PII-sanitized training sample and reward signal logged during
/// human feedback (RLHF) or post-mortem analysis.
class TrainingSample {
  final String id;
  final String notificationId;
  final String packageName;
  final String sanitizedTitle;
  final String sanitizedContent;
  final List<double> featureVector;
  final String predictedCategory;
  final double predictedScore;
  final double rewardSignal; // +1.0 for reward, -1.0 for penalty
  final String? correctedCategory;
  final String? correctedPriority;
  final int timestamp;
  final String modelVersion;
  final String engineVersion;

  const TrainingSample({
    required this.id,
    required this.notificationId,
    required this.packageName,
    required this.sanitizedTitle,
    required this.sanitizedContent,
    required this.featureVector,
    required this.predictedCategory,
    required this.predictedScore,
    required this.rewardSignal,
    this.correctedCategory,
    this.correctedPriority,
    required this.timestamp,
    required this.modelVersion,
    required this.engineVersion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'notificationId': notificationId,
      'packageName': packageName,
      'sanitizedTitle': sanitizedTitle,
      'sanitizedContent': sanitizedContent,
      'featureVector': featureVector,
      'predictedCategory': predictedCategory,
      'predictedScore': predictedScore,
      'rewardSignal': rewardSignal,
      'correctedCategory': correctedCategory,
      'correctedPriority': correctedPriority,
      'timestamp': timestamp,
      'modelVersion': modelVersion,
      'engineVersion': engineVersion,
    };
  }

  factory TrainingSample.fromMap(Map<String, dynamic> map) {
    return TrainingSample(
      id: map['id'] as String? ?? '',
      notificationId: map['notificationId'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      sanitizedTitle: map['sanitizedTitle'] as String? ?? '',
      sanitizedContent: map['sanitizedContent'] as String? ?? '',
      featureVector: (map['featureVector'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
      predictedCategory: map['predictedCategory'] as String? ?? 'unknown',
      predictedScore: (map['predictedScore'] as num?)?.toDouble() ?? 0.5,
      rewardSignal: (map['rewardSignal'] as num?)?.toDouble() ?? 0.0,
      correctedCategory: map['correctedCategory'] as String?,
      correctedPriority: map['correctedPriority'] as String?,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      modelVersion: map['modelVersion'] as String? ?? 'unknown',
      engineVersion: map['engineVersion'] as String? ?? 'unknown',
    );
  }

  /// Converts to Python dataset JSONL format matching training pipeline schema.
  Map<String, dynamic> toJsonlMap() {
    return {
      'id': id,
      'notification_id': notificationId,
      'package_name': packageName,
      'title': sanitizedTitle,
      'body': sanitizedContent,
      'features': featureVector,
      'category': correctedCategory ?? predictedCategory,
      'priority': correctedPriority ?? 'medium',
      'look_again_score': (predictedScore * 100).round(),
      'reward_signal': rewardSignal,
      'timestamp': timestamp,
      'model_version': modelVersion,
      'engine_version': engineVersion,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingSample &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          notificationId == other.notificationId &&
          packageName == other.packageName &&
          rewardSignal == other.rewardSignal &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      id.hashCode ^
      notificationId.hashCode ^
      packageName.hashCode ^
      rewardSignal.hashCode ^
      timestamp.hashCode;
}

