import 'package:flutter/foundation.dart';

/// Structured logger for storage operations and privacy-safe diagnostic telemetry.
/// Strictly redacts PII and sensitive user payload content.
class StorageLogger {
  StorageLogger._();

  static bool _debugMode = kDebugMode;

  @visibleForTesting
  static void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  /// Logs a structured storage cleanup event.
  static void logStorageCleanup({
    required int deletedCount,
    required int evictedCount,
    required int durationMs,
    required int totalRemaining,
  }) {
    final msg = '[STORAGE_CLEANUP] status=success deleted_expired=$deletedCount '
        'evicted_capacity=$evictedCount total_remaining=$totalRemaining duration_ms=$durationMs';
    if (_debugMode) {
      debugPrint(msg);
    }
  }

  /// Logs capacity limit or quota enforcement trigger.
  static void logCapacityEnforced({
    required int currentCount,
    required int maxCapacity,
    required int evictedCount,
  }) {
    final msg = '[STORAGE_QUOTA] action=evict current=$currentCount '
        'max_capacity=$maxCapacity evicted=$evictedCount';
    if (_debugMode) {
      debugPrint(msg);
    }
  }

  /// Logs storage error securely without leaking cleartext payload PII.
  static void logStorageError(String operation, Object error, [StackTrace? stackTrace]) {
    final sanitizedError = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
    final msg = '[STORAGE_ERROR] op=$operation error="${_redactPotentialPii(sanitizedError)}"';
    if (_debugMode) {
      debugPrint(msg);
      if (stackTrace != null && !sanitizedError.contains("Can't re-open a database")) {
        debugPrint(stackTrace.toString());
      }
    }
  }

  /// Redacts sensitive text strings or PII patterns.
  static String _redactPotentialPii(String text) {
    // Redact email patterns, credit card / phone numbers
    return text
        .replaceAll(RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[REDACTED_EMAIL]')
        .replaceAll(RegExp(r'\b\d{10,16}\b'), '[REDACTED_NUMBER]');
  }
}
