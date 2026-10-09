import 'dart:convert';
import 'package:scope/core/models/notification_model.dart';

/// Configuration policy for pre-ingestion notification guardrails.
class IngestionPolicy {
  final Set<String> blacklistedPackages;
  final Set<String> whitelistedPackages;
  final bool isWhitelistingEnabled;
  final Set<String> excludedCategories;
  final Set<String> sensitiveCategories;
  final int maxTitleLength;
  final int maxContentLength;

  const IngestionPolicy({
    this.blacklistedPackages = const {'com.android.systemui', 'android'},
    this.whitelistedPackages = const {},
    this.isWhitelistingEnabled = false,
    this.excludedCategories = const {
      'progress',
      'navigation',
      'service',
      'sys',
      'system',
      'transport',
      'status',
    },
    this.sensitiveCategories = const {},
    this.maxTitleLength = 500,
    this.maxContentLength = 2000,
  });

  factory IngestionPolicy.defaultPolicy() => const IngestionPolicy();

  IngestionPolicy copyWith({
    Set<String>? blacklistedPackages,
    Set<String>? whitelistedPackages,
    bool? isWhitelistingEnabled,
    Set<String>? excludedCategories,
    Set<String>? sensitiveCategories,
    int? maxTitleLength,
    int? maxContentLength,
  }) {
    return IngestionPolicy(
      blacklistedPackages: blacklistedPackages ?? this.blacklistedPackages,
      whitelistedPackages: whitelistedPackages ?? this.whitelistedPackages,
      isWhitelistingEnabled: isWhitelistingEnabled ?? this.isWhitelistingEnabled,
      excludedCategories: excludedCategories ?? this.excludedCategories,
      sensitiveCategories: sensitiveCategories ?? this.sensitiveCategories,
      maxTitleLength: maxTitleLength ?? this.maxTitleLength,
      maxContentLength: maxContentLength ?? this.maxContentLength,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blacklistedPackages': blacklistedPackages.toList(),
      'whitelistedPackages': whitelistedPackages.toList(),
      'isWhitelistingEnabled': isWhitelistingEnabled,
      'excludedCategories': excludedCategories.toList(),
      'sensitiveCategories': sensitiveCategories.toList(),
      'maxTitleLength': maxTitleLength,
      'maxContentLength': maxContentLength,
    };
  }

  factory IngestionPolicy.fromMap(Map<String, dynamic> map) {
    return IngestionPolicy(
      blacklistedPackages: Set<String>.from(map['blacklistedPackages'] ?? ['com.android.systemui', 'android']),
      whitelistedPackages: Set<String>.from(map['whitelistedPackages'] ?? []),
      isWhitelistingEnabled: map['isWhitelistingEnabled'] as bool? ?? false,
      excludedCategories: Set<String>.from(map['excludedCategories'] ?? ['progress', 'navigation', 'service', 'sys', 'system', 'transport', 'status']),
      sensitiveCategories: Set<String>.from(map['sensitiveCategories'] ?? []),
      maxTitleLength: (map['maxTitleLength'] as num?)?.toInt() ?? 500,
      maxContentLength: (map['maxContentLength'] as num?)?.toInt() ?? 2000,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory IngestionPolicy.fromJson(String source) =>
      IngestionPolicy.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// Audit log record for ingestion filtering actions.
class IngestionAuditLog {
  final DateTime timestamp;
  final String packageName;
  final String? dropReason;
  final bool isAllowed;

  IngestionAuditLog({
    DateTime? timestamp,
    required this.packageName,
    this.dropReason,
    required this.isAllowed,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'packageName': packageName,
      'dropReason': dropReason,
      'isAllowed': isAllowed,
    };
  }
}

/// Evaluation result for a notification passing or failing ingestion guardrails.
class IngestionGuardrailResult {
  final bool isAllowed;
  final String? dropReason;
  final AppNotification sanitizedNotification;

  const IngestionGuardrailResult({
    required this.isAllowed,
    this.dropReason,
    required this.sanitizedNotification,
  });
}

/// Pre-ingestion notification filtering service.
class IngestionGuardrailService {
  IngestionPolicy _policy;
  final List<IngestionAuditLog> _auditLogs = [];
  static const int maxAuditLogs = 100;

  IngestionGuardrailService({IngestionPolicy? policy})
      : _policy = policy ?? IngestionPolicy.defaultPolicy();

  IngestionPolicy get policy => _policy;
  List<IngestionAuditLog> get auditLogs => List.unmodifiable(_auditLogs);

  void updatePolicy(IngestionPolicy newPolicy) {
    _policy = newPolicy;
  }

  /// Evaluates an incoming [AppNotification] against configured guardrails and truncates boundaries.
  IngestionGuardrailResult evaluate(AppNotification notification) {
    try {
      final pkg = notification.packageName.trim();

      // 1. Ongoing / persistent notification check
      if (notification.isOngoing) {
        return _reject(notification, 'ongoing_notification', pkg);
      }

      // 2. Package blacklist check
      if (_policy.blacklistedPackages.contains(pkg)) {
        return _reject(notification, 'blacklisted_package', pkg);
      }

      // 3. Package whitelist check
      if (_policy.isWhitelistingEnabled && _policy.whitelistedPackages.isNotEmpty) {
        if (!_policy.whitelistedPackages.contains(pkg)) {
          return _reject(notification, 'not_whitelisted_package', pkg);
        }
      }

      // 4. Excluded category check
      final category = (notification.category ?? notification.classifiedCategory ?? '').toLowerCase().trim();
      final lowerExcluded = _policy.excludedCategories.map((c) => c.toLowerCase()).toSet();

      if (category.isNotEmpty && lowerExcluded.contains(category)) {
        return _reject(notification, 'excluded_category', pkg);
      }

      // Progress/system noise check if category matches progress keywords
      if (_isSystemProgressNotification(notification) && lowerExcluded.contains('progress')) {
        return _reject(notification, 'excluded_category', pkg);
      }

      // 5. Empty payload check
      if (notification.title.trim().isEmpty && notification.content.trim().isEmpty) {
        return _reject(notification, 'empty_payload', pkg);
      }

      // 6. String boundary truncations
      var title = notification.title;
      var content = notification.content;

      if (title.length > _policy.maxTitleLength) {
        title = title.substring(0, _policy.maxTitleLength);
      }
      if (content.length > _policy.maxContentLength) {
        content = content.substring(0, _policy.maxContentLength);
      }

      final sanitized = (title != notification.title || content != notification.content)
          ? notification.copyWith(title: title, content: content)
          : notification;

      _addAuditLog(pkg, null, true);

      return IngestionGuardrailResult(
        isAllowed: true,
        sanitizedNotification: sanitized,
      );
    } catch (e) {
      // Fallback error recovery path
      return _reject(notification, 'error_recovery', notification.packageName);
    }
  }

  IngestionGuardrailResult _reject(AppNotification notification, String reason, String pkg) {
    _addAuditLog(pkg, reason, false);
    return IngestionGuardrailResult(
      isAllowed: false,
      dropReason: reason,
      sanitizedNotification: notification,
    );
  }

  void _addAuditLog(String pkg, String? reason, bool allowed) {
    _auditLogs.add(IngestionAuditLog(
      packageName: pkg,
      dropReason: reason,
      isAllowed: allowed,
    ));
    if (_auditLogs.length > maxAuditLogs) {
      _auditLogs.removeAt(0);
    }
  }

  bool _isSystemProgressNotification(AppNotification notification) {
    final lowerTitle = notification.title.toLowerCase();
    final lowerContent = notification.content.toLowerCase();
    final combined = '$lowerTitle $lowerContent';

    const progressKeywords = [
      'downloading',
      'uploading',
      'sending file',
      'receiving file',
      'syncing',
      'backing up',
      'file transfer',
    ];

    for (final kw in progressKeywords) {
      if (combined.contains(kw)) return true;
    }
    return false;
  }
}
