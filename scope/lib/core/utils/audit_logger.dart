import 'package:flutter/foundation.dart';

/// Level of audit severity for timestamp expiry and scoring operations.
enum AuditLogLevel {
  info,
  warning,
  error,
}

/// A structured audit entry recorded on-device for expiry evaluation and scoring operations.
class AuditLogEntry {
  final DateTime timestamp;
  final AuditLogLevel level;
  final String category;
  final String message;
  final String? notificationId;

  const AuditLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.notificationId,
  });

  @override
  String toString() {
    return '[${timestamp.toIso8601String()}] [${level.name.toUpperCase()}] [$category] ${notificationId != null ? "($notificationId) " : ""}$message';
  }
}

/// Thread-safe, low-overhead, on-device audit logger with automatic PII redaction and
/// bounded memory retention for timestamp relative expiry evaluations and fallbacks.
class ExpiryAuditLogger {
  static ExpiryAuditLogger? _instance;
  static ExpiryAuditLogger get instance => _instance ??= ExpiryAuditLogger._();

  ExpiryAuditLogger._();

  static const int _maxLogCapacity = 100;
  final List<AuditLogEntry> _buffer = [];

  /// PII redaction regular expressions.
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b',
  );
  static final RegExp _otpDigitRegex = RegExp(
    r'\b\d{4,8}\b',
  );
  static final RegExp _amountRegex = RegExp(
    r'(?:₹|rs\.?|inr|usd|\$|eur|€)\s*\d+(?:\.\d+)?',
    caseSensitive: false,
  );

  /// Redacts sensitive PII from log string inputs before storing or printing.
  static String redactPii(String text) {
    var redacted = text;
    redacted = redacted.replaceAllMapped(_emailRegex, (_) => '[EMAIL_REDACTED]');
    redacted = redacted.replaceAllMapped(_phoneRegex, (_) => '[PHONE_REDACTED]');
    redacted = redacted.replaceAllMapped(_amountRegex, (_) => '[AMOUNT_REDACTED]');
    redacted = redacted.replaceAllMapped(_otpDigitRegex, (m) {
      final val = m.group(0)!;
      // Preserve years 2020..2030, redact other 4-8 digit numbers
      final num = int.tryParse(val);
      if (num != null && num >= 2020 && num <= 2030) return val;
      return '[OTP_REDACTED]';
    });
    return redacted;
  }

  /// Records an audit log entry with automatic PII redaction.
  void log({
    required AuditLogLevel level,
    required String category,
    required String message,
    String? notificationId,
  }) {
    final entry = AuditLogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: redactPii(message),
      notificationId: notificationId,
    );

    if (_buffer.length >= _maxLogCapacity) {
      _buffer.removeAt(0);
    }
    _buffer.add(entry);

    if (kDebugMode) {
      debugPrint('AUDIT: $entry');
    }
  }

  /// Helper for logging relative expiry evaluation decisions.
  void logExpiryEvaluation({
    required String notificationId,
    required String type,
    required bool isExpired,
    required String reason,
  }) {
    log(
      level: AuditLogLevel.info,
      category: 'ExpiryEvaluation',
      message: 'Type: $type | Expired: $isExpired | Reason: $reason',
      notificationId: notificationId,
    );
  }

  /// Helper for logging timestamp normalization actions.
  void logTimestampNormalization({
    required String notificationId,
    required int rawTimestamp,
    required int normalizedTimestamp,
    required String action,
  }) {
    log(
      level: AuditLogLevel.info,
      category: 'TimestampNormalization',
      message: 'Raw: $rawTimestamp -> Normalized: $normalizedTimestamp ($action)',
      notificationId: notificationId,
    );
  }

  /// Helper for logging fallback error recovery execution.
  void logFallbackRecovery({
    required String notificationId,
    required String component,
    required String error,
    required String fallbackAction,
  }) {
    log(
      level: AuditLogLevel.warning,
      category: 'FallbackRecovery',
      message: 'Component: $component | Error: $error | Action: $fallbackAction',
      notificationId: notificationId,
    );
  }

  /// Returns an unmodifiable snapshot of buffered audit log entries.
  List<AuditLogEntry> get logs => List.unmodifiable(_buffer);

  /// Clears the in-memory log buffer (useful for unit testing).
  void clear() {
    _buffer.clear();
  }
}
