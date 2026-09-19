library;

/// Static redaction mask placeholders for sensitive PII categories.
abstract final class PiiRedactionMasks {
  static const String otp = '[REDACTED_OTP]';
  static const String amount = '[REDACTED_AMOUNT]';
  static const String url = '[REDACTED_URL]';
  static const String email = '[REDACTED_EMAIL]';
  static const String phoneNumber = '[REDACTED_PHONE]';
  static const String generic = '[REDACTED]';
}

/// Utility for dual-layer PII sanitization and UI masking.
abstract final class PiiSanitizer {
  /// Sanitizes sensitive fields in an extracted features Map.
  ///
  /// Replaces cleartext OTPs, transaction amounts, URLs, emails, and phone
  /// numbers with static redaction masks, while leaving structural keys
  /// (`hasDeadline`, `deadline_minutes_remaining`, etc.) intact.
  static Map<String, dynamic> sanitizeFeatureMap(Map<String, dynamic>? map) {
    if (map == null) return {};
    final sanitized = Map<String, dynamic>.from(map);

    if (sanitized.containsKey('otp') && sanitized['otp'] != null) {
      sanitized['otp'] = PiiRedactionMasks.otp;
    }

    if (sanitized.containsKey('amount') && sanitized['amount'] != null) {
      sanitized['amount'] = PiiRedactionMasks.amount;
    }

    if (sanitized.containsKey('urls') && sanitized['urls'] != null) {
      final urlsList = sanitized['urls'] as Iterable?;
      if (urlsList != null && urlsList.isNotEmpty) {
        sanitized['urls'] = List<String>.generate(
          urlsList.length,
          (_) => PiiRedactionMasks.url,
        );
      }
    }

    if (sanitized.containsKey('emails') && sanitized['emails'] != null) {
      final emailsList = sanitized['emails'] as Iterable?;
      if (emailsList != null && emailsList.isNotEmpty) {
        sanitized['emails'] = List<String>.generate(
          emailsList.length,
          (_) => PiiRedactionMasks.email,
        );
      }
    }

    if (sanitized.containsKey('phoneNumbers') && sanitized['phoneNumbers'] != null) {
      final phoneList = sanitized['phoneNumbers'] as Iterable?;
      if (phoneList != null && phoneList.isNotEmpty) {
        sanitized['phoneNumbers'] = List<String>.generate(
          phoneList.length,
          (_) => PiiRedactionMasks.phoneNumber,
        );
      }
    }

    return sanitized;
  }
}
