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

  const AppNotification({
    required this.id,
    required this.packageName,
    required this.title,
    required this.content,
    required this.timestamp,
    this.category,
    this.isOngoing = false,
  });

  /// Creates an [AppNotification] from a Map (used by MethodChannel bridge).
  ///
  /// Expects keys: 'id', 'packageName', 'title', 'content', 'timestamp',
  /// 'category', 'isOngoing'.
  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      category: map['category'] as String?,
      isOngoing: map['isOngoing'] as bool? ?? false,
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
        other.isOngoing == isOngoing;
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
      );

  @override
  String toString() {
    return 'AppNotification(id: $id, package: $packageName, '
        'title: $title, content: $content, '
        'timestamp: $timestamp, category: $category, '
        'isOngoing: $isOngoing)';
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
  }) {
    return AppNotification(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      title: title ?? this.title,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      isOngoing: isOngoing ?? this.isOngoing,
    );
  }
}
