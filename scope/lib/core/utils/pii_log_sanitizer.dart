import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';

/// Configurable sanitization modes for PII logging.
enum SanitizationMode {
  /// Masked placeholder format, e.g. `[REDACTED (12 chars)]`
  masked,

  /// Structural metadata format, e.g. `[title_len=12, sha256=a1b2c345]`
  metadata,

  /// Non-sensitive digest format, e.g. `[sha256=a1b2c345]`
  digest,
}

/// Centralized log sanitization helper for redacting raw notification titles,
/// body contents, and sensitive tokens into structural metadata before logging
/// to system Logcat buffers or debug console streams.
class PiiLogSanitizer {
  PiiLogSanitizer._();

  /// Computes a truncated SHA-256 hash digest hex string.
  static String sha256Digest(String? input, {int length = 8}) {
    if (input == null || input.isEmpty) return 'empty';
    try {
      final bytes = utf8.encode(input);
      final digest = crypto.sha256.convert(bytes).toString();
      if (length > 0 && length < digest.length) {
        return digest.substring(0, length);
      }
      return digest;
    } catch (_) {
      return 'error';
    }
  }

  /// Redacts string input into structural metadata based on [mode].
  static String sanitize(
    String? input, {
    SanitizationMode mode = SanitizationMode.masked,
    String? label,
  }) {
    try {
      if (input == null) {
        final lbl = (label != null && label.isNotEmpty) ? '${label}_len' : 'str_len';
        switch (mode) {
          case SanitizationMode.masked:
            return '[REDACTED]';
          case SanitizationMode.digest:
            return '[sha256=null]';
          case SanitizationMode.metadata:
            return '[$lbl=0, sha256=null]';
        }
      }

      final len = input.length;
      switch (mode) {
        case SanitizationMode.masked:
          return '[REDACTED ($len chars)]';
        case SanitizationMode.digest:
          return '[sha256=${sha256Digest(input)}]';
        case SanitizationMode.metadata:
          final lbl = (label != null && label.isNotEmpty) ? '${label}_len' : 'len';
          return '[$lbl=$len, sha256=${sha256Digest(input)}]';
      }
    } catch (_) {
      return '[REDACTED]';
    }
  }

  /// Shortcut to mask string content with character count: `[REDACTED (X chars)]`.
  static String mask(String? input) {
    return sanitize(input, mode: SanitizationMode.masked);
  }

  /// Shortcut to format string into metadata format: `[title_len=X, sha256=Y]`.
  static String toMetadata(String? input, {String? label}) {
    return sanitize(input, mode: SanitizationMode.metadata, label: label);
  }

  /// Sanitizes exception details to prevent leaking PII or raw payload data.
  static String sanitizeException(Object? error) {
    if (error == null) return 'Exception(null)';
    try {
      if (error is PlatformException) {
        final sanitizedMsg = error.message != null
            ? mask(error.message)
            : '[no message]';
        return 'PlatformException(code: ${error.code}, message: $sanitizedMsg)';
      }
      final str = error.toString();
      return mask(str);
    } catch (_) {
      return 'Exception(sanitization_failed)';
    }
  }
}
