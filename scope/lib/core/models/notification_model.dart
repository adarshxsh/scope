/// Core notification data model for AttentionOS.
///
/// Represents a single captured Android notification.
/// Designed to be platform-agnostic on the Dart side so it can be
/// used in tests without any Android dependency.
library;

class AppNotification {
  /// Unique identifier for this notification instance.
  final String id;

  /// Android package name of the app that posted the notification.
  /// Example: "com.whatsapp", "com.google.android.gm"
  final String packageName;

  /// Notification title (may be empty for some notifications).
  final String title;

  /// Notification body/content text.
  final String content;

  /// Unix timestamp in milliseconds when the notification was posted.
  final int timestamp;

  /// Raw category string from Android (e.g., "msg", "email", "promo").
  /// Null if Android didn't assign a category.
  final String? category;

  /// Whether this is an ongoing/persistent notification.
  final bool isOngoing;

  /// Priority level resolved by Ghost AI ('critical' | 'high' | 'medium' | 'low').
  final String? priority;

  /// Score supporting priority resolution (0.0 to 1.0).
  final double? priorityScore;

  /// Category classified by Ghost AI.
  final String? classifiedCategory;

  /// Natural language explanation of how the priority was determined.
  final String? explanation;

  /// Processing latency of the analysis pipeline in milliseconds.
  final int? latencyMs;

  /// Version of the JSON rules matching database.
  final String? ruleVersion;

  /// Version of the classification model.
  final String? modelVersion;

  /// Version of the analysis pipeline software.
  final String? engineVersion;

  /// Structured features extracted from the text elements.
  final Map<String, dynamic>? extractedFeatures;

  const AppNotification({
    required this.id,
    required this.packageName,
    required this.title,
    required this.content,
    required this.timestamp,
    this.category,
    this.isOngoing = false,
    this.priority,
    this.priorityScore,
    this.classifiedCategory,
    this.explanation,
    this.latencyMs,
    this.ruleVersion,
    this.modelVersion,
    this.engineVersion,
    this.extractedFeatures,
  });

  /// Creates an [AppNotification] from a Map (used by MethodChannel bridge).
  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      category: map['category'] as String?,
      isOngoing: map['isOngoing'] as bool? ?? false,
      priority: map['priority'] as String?,
      priorityScore: (map['priorityScore'] as num?)?.toDouble(),
      classifiedCategory: map['classifiedCategory'] as String?,
      explanation: map['explanation'] as String?,
      latencyMs: map['latencyMs'] as int?,
      ruleVersion: map['ruleVersion'] as String?,
      modelVersion: map['modelVersion'] as String?,
      engineVersion: map['engineVersion'] as String?,
      extractedFeatures: map['extractedFeatures'] != null
          ? Map<String, dynamic>.from(map['extractedFeatures'] as Map)
          : null,
    );
  }

  /// Converts this notification to a Map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'packageName': packageName,
      'title': title,
      'content': content,
      'timestamp': timestamp,
      'category': category,
      'isOngoing': isOngoing,
      'priority': priority,
      'priorityScore': priorityScore,
      'classifiedCategory': classifiedCategory,
      'explanation': explanation,
      'latencyMs': latencyMs,
      'ruleVersion': ruleVersion,
      'modelVersion': modelVersion,
      'engineVersion': engineVersion,
      'extractedFeatures': extractedFeatures,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppNotification &&
        other.id == id &&
        other.packageName == packageName &&
        other.title == title &&
        other.content == content &&
        other.timestamp == timestamp &&
        other.category == category &&
        other.isOngoing == isOngoing &&
        other.priority == priority &&
        other.priorityScore == priorityScore &&
        other.classifiedCategory == classifiedCategory &&
        other.explanation == explanation &&
        other.latencyMs == latencyMs &&
        other.ruleVersion == ruleVersion &&
        other.modelVersion == modelVersion &&
        other.engineVersion == engineVersion &&
        _mapsEqual(other.extractedFeatures, extractedFeatures);
  }

  static bool _mapsEqual(Map? a, Map? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        packageName,
        title,
        content,
        timestamp,
        category,
        isOngoing,
        priority,
        priorityScore,
        classifiedCategory,
        explanation,
        latencyMs,
        ruleVersion,
        modelVersion,
        engineVersion,
        extractedFeatures?.length,
      );

  @override
  String toString() {
    return 'AppNotification(id: $id, package: $packageName, '
        'title: $title, content: $content, '
        'timestamp: $timestamp, category: $category, '
        'isOngoing: $isOngoing, priority: $priority, '
        'priorityScore: $priorityScore, classifiedCategory: $classifiedCategory, '
        'explanation: $explanation, latencyMs: $latencyMs, '
        'ruleVersion: $ruleVersion, modelVersion: $modelVersion, '
        'engineVersion: $engineVersion, extractedFeatures: $extractedFeatures)';
  }

  /// Creates a copy with optional field overrides.
  AppNotification copyWith({
    String? id,
    String? packageName,
    String? title,
    String? content,
    int? timestamp,
    String? category,
    bool? isOngoing,
    String? priority,
    double? priorityScore,
    String? classifiedCategory,
    String? explanation,
    int? latencyMs,
    String? ruleVersion,
    String? modelVersion,
    String? engineVersion,
    Map<String, dynamic>? extractedFeatures,
  }) {
    return AppNotification(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      title: title ?? this.title,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      isOngoing: isOngoing ?? this.isOngoing,
      priority: priority ?? this.priority,
      priorityScore: priorityScore ?? this.priorityScore,
      classifiedCategory: classifiedCategory ?? this.classifiedCategory,
      explanation: explanation ?? this.explanation,
      latencyMs: latencyMs ?? this.latencyMs,
      ruleVersion: ruleVersion ?? this.ruleVersion,
      modelVersion: modelVersion ?? this.modelVersion,
      engineVersion: engineVersion ?? this.engineVersion,
      extractedFeatures: extractedFeatures ?? this.extractedFeatures,
    );
  }
}
