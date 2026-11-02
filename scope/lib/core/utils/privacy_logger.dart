import 'package:flutter/foundation.dart';

/// Structured telemetry and diagnostic logger with zero PII exposure guardrails.
class PrivacyLogger {
  PrivacyLogger._();

  /// Masks potential PII (OTPs, phone numbers, email addresses, financial details) in text.
  static String maskPII(String text) {
    if (text.isEmpty) return text;

    String sanitized = text;

    // Mask email addresses
    sanitized = sanitized.replaceAll(
      RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
      '[EMAIL]',
    );

    // Mask phone numbers (E.164 or common formatted numbers)
    sanitized = sanitized.replaceAll(
      RegExp(r'(\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}'),
      '[PHONE]',
    );

    // Mask currency / financial amounts (e.g. $100, ₹5,000, Rs 500)
    sanitized = sanitized.replaceAll(
      RegExp(r'(?:[\$₹]|Rs\.?\s?)\d+(?:,\d+)*(?:\.\d+)?', caseSensitive: false),
      '[AMOUNT]',
    );

    // Mask standalone 4-8 digit OTP codes
    sanitized = sanitized.replaceAll(RegExp(r'\b\d{4,8}\b'), '[OTP]');

    return sanitized;
  }

  /// Truncates string and masks PII for diagnostic tracing.
  static String safeSummary(String text, {int maxLength = 30}) {
    final masked = maskPII(text);
    if (masked.length <= maxLength) return masked;
    return '${masked.substring(0, maxLength)}...';
  }

  /// Logs ML inference execution without exposing cleartext PII.
  static void logInference({
    required String packageName,
    required int latencyMs,
    required String priority,
    required String category,
    required bool cacheHit,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[Telemetry:Inference] pkg: $packageName | priority: $priority | cat: $category | latency: ${latencyMs}ms | cacheHit: $cacheHit',
      );
    }
  }

  /// Logs polling interval and count metadata.
  static void logPolling({
    required int fetchedCount,
    required int totalCount,
    required int intervalSeconds,
    required int consecutiveEmptyPolls,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[Telemetry:Polling] fetched: $fetchedCount | totalCount: $totalCount | interval: ${intervalSeconds}s | emptyPolls: $consecutiveEmptyPolls',
      );
    }
  }

  /// Logs error events with masked context.
  static void logError(String context, Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      final maskedContext = maskPII(context);
      debugPrint('[Telemetry:Error] [$maskedContext] $error');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    }
  }
}
