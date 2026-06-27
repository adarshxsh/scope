/// Core notification data model for AttentionOS.
///
/// Represents a single captured Android notification.
/// Designed to be platform-agnostic on the Dart side so it can be
/// used in tests without any Android dependency.
library;

/// The review state of a notification in the Review Queue.
enum ReviewState {
  // ignore: constant_identifier_names
  ACTIVE,
  // ignore: constant_identifier_names
  SNOOZED,
  // ignore: constant_identifier_names
  REVIEWED,
  // ignore: constant_identifier_names
  EXPIRED,
  // ignore: constant_identifier_names
  ARCHIVED,
}

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

  /// Review state in the Review Queue.
  final ReviewState state;

  /// Time until which the notification is snoozed.
  final DateTime? snoozedUntil;

  /// Time when the notification was last updated in the queue.
  final DateTime? lastUpdated;

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
    this.state = ReviewState.ACTIVE,
    this.snoozedUntil,
    this.lastUpdated,
  });

  /// Generates a stable unique ID based on notification properties.
  static String generateStableId({
    required String packageName,
    required int timestamp,
    required String title,
    required String content,
  }) {
    final pkgHash = _stableHash(packageName);
    final titleHash = _stableHash(title);
    final contentHash = _stableHash(content);
    return '${pkgHash}_${timestamp}_${titleHash}_$contentHash';
  }

  static int _stableHash(String val) {
    int hash = 5381;
    for (int i = 0; i < val.length; i++) {
      hash = ((hash << 5) + hash) + val.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Creates an [AppNotification] from a Map (used by MethodChannel bridge).
  factory AppNotification.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'] as String? ?? '';
    final packageName = map['packageName'] as String? ?? '';
    final title = map['title'] as String? ?? '';
    final content = map['content'] as String? ?? '';
    final timestamp = map['timestamp'] as int? ?? 0;

    final id = (rawId.isEmpty || rawId.startsWith('notif_'))
        ? (packageName.isEmpty && title.isEmpty && content.isEmpty && timestamp == 0)
            ? ''
            : AppNotification.generateStableId(
                packageName: packageName,
                timestamp: timestamp,
                title: title,
                content: content,
              )
        : rawId;

    return AppNotification(
      id: id,
      packageName: packageName,
      title: title,
      content: content,
      timestamp: timestamp,
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
      state: _parseReviewState(map['state']),
      snoozedUntil: map['snoozedUntil'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['snoozedUntil'] as int)
          : null,
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int)
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
      'state': state.name,
      'snoozedUntil': snoozedUntil?.millisecondsSinceEpoch,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
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
        other.state == state &&
        other.snoozedUntil == snoozedUntil &&
        other.lastUpdated == lastUpdated &&
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
        state,
        snoozedUntil,
        lastUpdated,
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
        'engineVersion: $engineVersion, state: $state, '
        'snoozedUntil: $snoozedUntil, lastUpdated: $lastUpdated, '
        'extractedFeatures: $extractedFeatures)';
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
    ReviewState? state,
    DateTime? snoozedUntil,
    DateTime? lastUpdated,
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
      state: state ?? this.state,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Helper function to safely parse ReviewState from a serialized value.
ReviewState _parseReviewState(dynamic stateVal) {
  if (stateVal == null) return ReviewState.ACTIVE;
  final name = stateVal.toString();
  for (final value in ReviewState.values) {
    if (value.name == name ||
        value.toString() == name ||
        value.toString().split('.').last == name) {
      return value;
    }
  }
  return ReviewState.ACTIVE;
}
