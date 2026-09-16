import 'package:scope/core/models/notification_model.dart';

/// Privacy and Sanitization Guardrails for AttentionOS.
///
/// Ensures strict PII (Personally Identifiable Information) redaction,
/// on-device privacy compliance, and schema validation before persistence
/// or telemetry logging.
class PrivacySanitizer {
  // Regex patterns for sensitive PII data
  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  static final RegExp _phoneRegex = RegExp(
    r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b',
  );

  static final RegExp _otpRegex = RegExp(
    r'\b(?:\d{4,8}|[A-Z0-9]{6,8})\b',
  );

  static final RegExp _accountCardRegex = RegExp(
    r'\b(?:\d[ -]*?){12,19}\b',
  );

  /// Sanitize arbitrary text by redacting sensitive PII patterns.
  static String sanitizeText(String input) {
    if (input.isEmpty) return input;

    String sanitized = input;

    // 1. Redact credit card / account numbers
    sanitized = sanitized.replaceAllMapped(_accountCardRegex, (match) {
      final val = match.group(0)!;
      // Skip short matches or year numbers
      if (val.length < 10) return val;
      return '[REDACTED_ACCOUNT]';
    });

    // 2. Redact emails
    sanitized = sanitized.replaceAll(_emailRegex, '[REDACTED_EMAIL]');

    // 3. Redact phone numbers
    sanitized = sanitized.replaceAll(_phoneRegex, '[REDACTED_PHONE]');

    // 4. Redact OTPs if context keywords are present
    final lower = sanitized.toLowerCase();
    if (lower.contains('otp') ||
        lower.contains('code') ||
        lower.contains('verification') ||
        lower.contains('verify') ||
        lower.contains('pin')) {
      sanitized = sanitized.replaceAllMapped(_otpRegex, (match) {
        final val = match.group(0)!;
        // Don't redact common short words
        if (RegExp(r'^(code|pin|pass|user|auth)$', caseSensitive: false).hasMatch(val)) {
          return val;
        }
        return '[REDACTED_OTP]';
      });
    }

    return sanitized;
  }

  /// Sanitize an entire AppNotification before logging or exporting.
  static AppNotification sanitizeNotification(AppNotification notification) {
    return notification.copyWith(
      title: sanitizeText(notification.title),
      content: sanitizeText(notification.content),
      explanation: notification.explanation != null ? sanitizeText(notification.explanation!) : null,
    );
  }

  /// Returns whether a text contains potential cleartext PII.
  static bool hasPII(String text) {
    if (text.isEmpty) return false;
    return _emailRegex.hasMatch(text) ||
        _phoneRegex.hasMatch(text) ||
        _accountCardRegex.hasMatch(text);
  }

  /// Validates schema rules for an AppNotification.
  /// Throws FormatException if schema rules are violated.
  static bool validateNotificationSchema(AppNotification notification) {
    if (notification.id.trim().isEmpty) {
      throw const FormatException('Notification ID cannot be empty');
    }
    if (notification.timestamp <= 0) {
      throw const FormatException('Invalid notification timestamp');
    }
    if (notification.title.length > 512) {
      throw const FormatException('Notification title exceeds maximum length (512 chars)');
    }
    if (notification.content.length > 4096) {
      throw const FormatException('Notification content exceeds maximum length (4096 chars)');
    }
    if (notification.priority != null) {
      final p = notification.priority!.toLowerCase();
      if (!['critical', 'high', 'medium', 'low'].contains(p)) {
        throw FormatException('Invalid priority level: ${notification.priority}');
      }
    }
    return true;
  }
}
