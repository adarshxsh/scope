import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_actions.dart';

/// Validation status codes for Smart Action URL launching and Intent redirection.
enum ValidationStatus {
  valid,
  invalidScheme,
  blockedIntentRedirection,
  blockedLoopbackHost,
  blockedUserinfo,
  invalidHost,
  invalidPackageName,
  malformedUrl,
  missingTarget,
}

/// Result of validating a Smart Action URL or Intent target.
class SmartActionValidationResult {
  final bool isValid;
  final ValidationStatus status;
  final String? sanitizedUrl;
  final String? targetPackage;
  final String reason;
  final String? redactedUrlForAudit;

  const SmartActionValidationResult({
    required this.isValid,
    required this.status,
    this.sanitizedUrl,
    this.targetPackage,
    required this.reason,
    this.redactedUrlForAudit,
  });

  const SmartActionValidationResult.valid({
    this.sanitizedUrl,
    this.targetPackage,
    this.reason = 'Target is valid and allowed.',
    this.redactedUrlForAudit,
  })  : isValid = true,
        status = ValidationStatus.valid;

  const SmartActionValidationResult.invalid({
    required this.status,
    required this.reason,
    this.redactedUrlForAudit,
    this.targetPackage,
  })  : isValid = false,
        sanitizedUrl = null;
}

/// Audit log record for Smart Action URL and Intent launching attempts.
class ActionAuditLogEntry {
  final DateTime timestamp;
  final String notificationId;
  final SmartActionType actionType;
  final String? originalUrlRedacted;
  final String? targetPackage;
  final ValidationStatus status;
  final bool isAllowed;
  final String reason;

  ActionAuditLogEntry({
    DateTime? timestamp,
    required this.notificationId,
    required this.actionType,
    this.originalUrlRedacted,
    this.targetPackage,
    required this.status,
    required this.isAllowed,
    required this.reason,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'notificationId': notificationId,
      'actionType': actionType.name,
      'originalUrlRedacted': originalUrlRedacted,
      'targetPackage': targetPackage,
      'status': status.name,
      'isAllowed': isAllowed,
      'reason': reason,
    };
  }

  @override
  String toString() {
    return 'ActionAuditLogEntry(timestamp: $timestamp, notificationId: $notificationId, '
        'actionType: ${actionType.name}, status: ${status.name}, isAllowed: $isAllowed, '
        'url: $originalUrlRedacted, pkg: $targetPackage, reason: $reason)';
  }
}

/// Centralized validator enforcing security, privacy, and intent guardrails
/// for Smart Action URL launching and Intent redirection.
abstract final class SmartActionValidator {
  static const Set<String> _allowedSchemes = {
    'https',
    'http',
    'mailto',
    'tel',
    'sms',
  };

  static const Set<String> _blockedSchemes = {
    'javascript',
    'file',
    'data',
    'content',
    'intent',
    'blob',
    'vbscript',
    'about',
    'chrome',
    'android-app',
  };

  static const Set<String> _sensitiveQueryParams = {
    'token',
    'auth',
    'authorization',
    'password',
    'pass',
    'pwd',
    'secret',
    'key',
    'api_key',
    'apikey',
    'access_token',
    'otp',
    'session',
    'cookie',
    'jwt',
    'credential',
    'credentials',
  };

  static final RegExp _packageNameRegex =
      RegExp(r'^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$');

  static const int _maxAuditLogs = 100;
  static final List<ActionAuditLogEntry> _auditLogs = [];

  /// Returns an unmodifiable snapshot of recent audit log entries.
  static List<ActionAuditLogEntry> get auditLogs =>
      List.unmodifiable(_auditLogs);

  /// Clears audit logs (useful for unit tests and storage resets).
  static void clearAuditLogs() {
    _auditLogs.clear();
  }

  /// Records an audit log entry in a bounded memory buffer.
  static void recordAuditLog(ActionAuditLogEntry entry) {
    if (_auditLogs.length >= _maxAuditLogs) {
      _auditLogs.removeAt(0);
    }
    _auditLogs.add(entry);
  }

  /// Validates a raw URL string against scheme, host, intent redirection,
  /// and PII exposure guardrails.
  static SmartActionValidationResult validateUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return const SmartActionValidationResult.invalid(
        status: ValidationStatus.missingTarget,
        reason: 'URL target is missing or empty.',
      );
    }

    final trimmed = rawUrl.trim();
    final lower = trimmed.toLowerCase();

    // Guardrail 1: Detect intent parameter hijacking & raw intent:// URIs
    if (lower.startsWith('intent://') ||
        lower.contains('#intent;') ||
        lower.contains('component=') ||
        lower.contains('s.browser_fallback_url=')) {
      final redacted = redactPiiFromUrl(trimmed);
      return SmartActionValidationResult.invalid(
        status: ValidationStatus.blockedIntentRedirection,
        reason: 'Blocked intent redirection URI or embedded intent parameters.',
        redactedUrlForAudit: redacted,
      );
    }

    // Guardrail 2: Explicit scheme check for known blocked schemes
    for (final scheme in _blockedSchemes) {
      if (lower.startsWith('$scheme:')) {
        final redacted = redactPiiFromUrl(trimmed);
        return SmartActionValidationResult.invalid(
          status: ValidationStatus.invalidScheme,
          reason: 'Blocked dangerous URI scheme: $scheme',
          redactedUrlForAudit: redacted,
        );
      }
    }

    // Normalize URL scheme if missing (e.g. www.example.com -> https://www.example.com)
    String normalized = trimmed;
    if (!normalized.contains('://')) {
      if (normalized.startsWith('www.') || normalized.contains('.')) {
        normalized = 'https://$normalized';
      } else {
        return SmartActionValidationResult.invalid(
          status: ValidationStatus.malformedUrl,
          reason: 'URL is missing valid scheme or domain structure.',
          redactedUrlForAudit: redactPiiFromUrl(trimmed),
        );
      }
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return SmartActionValidationResult.invalid(
        status: ValidationStatus.malformedUrl,
        reason: 'Failed to parse URI structure.',
        redactedUrlForAudit: redactPiiFromUrl(trimmed),
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (!_allowedSchemes.contains(scheme)) {
      return SmartActionValidationResult.invalid(
        status: ValidationStatus.invalidScheme,
        reason: 'Unsupported URI scheme: $scheme. Allowed: ${_allowedSchemes.join(", ")}',
        redactedUrlForAudit: redactPiiFromUrl(trimmed),
      );
    }

    // Web URLs (http/https) require host and security checks
    if (scheme == 'http' || scheme == 'https') {
      if (uri.host.isEmpty) {
        return SmartActionValidationResult.invalid(
          status: ValidationStatus.invalidHost,
          reason: 'Web URL must contain a valid host.',
          redactedUrlForAudit: redactPiiFromUrl(trimmed),
        );
      }

      final hostLower = uri.host.toLowerCase();
      if (hostLower == 'localhost' ||
          hostLower == '127.0.0.1' ||
          hostLower == '::1' ||
          hostLower == '0.0.0.0') {
        return SmartActionValidationResult.invalid(
          status: ValidationStatus.blockedLoopbackHost,
          reason: 'Blocked loopback/local IP host to prevent local service abuse.',
          redactedUrlForAudit: redactPiiFromUrl(trimmed),
        );
      }

      if (uri.userInfo.isNotEmpty) {
        return SmartActionValidationResult.invalid(
          status: ValidationStatus.blockedUserinfo,
          reason: 'Blocked embedded credentials/userInfo in URL target.',
          redactedUrlForAudit: redactPiiFromUrl(trimmed),
        );
      }
    }

    final sanitized = sanitizeUrl(uri);
    final redactedForAudit = redactPiiFromUrl(sanitized);

    return SmartActionValidationResult.valid(
      sanitizedUrl: sanitized,
      reason: 'URL target verified successfully.',
      redactedUrlForAudit: redactedForAudit,
    );
  }

  /// Validates an Android package name format.
  static SmartActionValidationResult validatePackageName(String? packageName) {
    if (packageName == null || packageName.trim().isEmpty) {
      return const SmartActionValidationResult.invalid(
        status: ValidationStatus.missingTarget,
        reason: 'Package name is missing or empty.',
      );
    }

    final pkg = packageName.trim();
    if (!_packageNameRegex.hasMatch(pkg)) {
      return SmartActionValidationResult.invalid(
        status: ValidationStatus.invalidPackageName,
        reason: 'Malformed package name format: $pkg',
        targetPackage: pkg,
      );
    }

    return SmartActionValidationResult.valid(
      targetPackage: pkg,
      reason: 'Package name verified successfully.',
    );
  }

  /// Evaluates guardrails for a SmartAction and AppNotification.
  static SmartActionValidationResult validateAction(
    SmartAction action,
    AppNotification notification,
  ) {
    switch (action.type) {
      case SmartActionType.openUrl:
      case SmartActionType.join:
      case SmartActionType.download:
        final targetUrl = action.url ?? _firstExtractedUrl(notification);
        return validateUrl(targetUrl);

      case SmartActionType.track:
        if (action.url != null && action.url!.isNotEmpty) {
          final urlResult = validateUrl(action.url);
          if (urlResult.isValid) return urlResult;
        }
        final extractedUrl = _firstExtractedUrl(notification);
        if (extractedUrl != null) {
          final urlResult = validateUrl(extractedUrl);
          if (urlResult.isValid) return urlResult;
        }
        return validatePackageName(
            action.packageName ?? notification.packageName);

      case SmartActionType.openApp:
      case SmartActionType.pay:
      case SmartActionType.viewStatement:
      case SmartActionType.reply:
        return validatePackageName(
            action.packageName ?? notification.packageName);

      case SmartActionType.addCalendar:
      case SmartActionType.remind:
      case SmartActionType.archive:
      case SmartActionType.complete:
        return const SmartActionValidationResult.valid(
          reason: 'Internal action requires no external launcher.',
        );
    }
  }

  /// Sanitizes sensitive query parameters from a Uri.
  static String sanitizeUrl(Uri uri) {
    if (!uri.hasQuery) return uri.toString();

    final queryMap = Map<String, String>.from(uri.queryParameters);
    var modified = false;

    for (final key in queryMap.keys.toList()) {
      final keyLower = key.toLowerCase();
      if (_sensitiveQueryParams.contains(keyLower)) {
        queryMap[key] = '[REDACTED]';
        modified = true;
      }
    }

    if (!modified) return uri.toString();

    return uri.replace(queryParameters: queryMap).toString();
  }

  /// Redacts sensitive query parameters, emails, and credentials for logging.
  static String redactPiiFromUrl(String url) {
    var result = url;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      result = sanitizeUrl(uri);
    }
    // Mask email patterns (both raw @ and percent-encoded %40) in path or query
    result = result.replaceAll(
      RegExp(r'[a-zA-Z0-9._%+-]+(?:@|%40)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', caseSensitive: false),
      '[REDACTED_EMAIL]',
    );
    return result;
  }

  static String? _firstExtractedUrl(AppNotification notification) {
    final features = notification.extractedFeatures;
    if (features != null && features['urls'] is List) {
      final list = features['urls'] as List;
      if (list.isNotEmpty && list.first is String) {
        return list.first as String;
      }
    }
    return null;
  }
}
