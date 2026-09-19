import 'package:flutter/foundation.dart';

/// Centralized utility for redacting sensitive PII (Personally Identifiable Information)
/// and authentication data in notification titles, content, diagnostic logs,
/// and telemetry data before persistence, system logging, or UI rendering.
class PiiRedactor {
  PiiRedactor._();

  // Credit/Debit Card pattern (13 to 19 digits, optional spaces/dashes)
  static final RegExp _cardRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  // Email Address pattern
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    caseSensitive: false,
  );

  // URL / Web Link pattern
  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s]+|www\.[^\s]+',
    caseSensitive: false,
  );

  // Monetary Amounts & Currency values pattern
  static final RegExp _monetaryRegex = RegExp(
    r'(?:[\$₹€£]|USD|INR|EUR|GBP|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?|\b[\d,]+(?:\.\d{1,2})?\s*(?:USD|INR|EUR|GBP|dollars|rupees|Rs\.?)\b',
    caseSensitive: false,
  );

  // JWT / Auth tokens / API Keys / Bearer tokens pattern
  static final RegExp _tokenRegex = RegExp(
    r'bearer\s+[a-zA-Z0-9\-\._~\+\/]+=*|\b[A-Fa-f0-9]{32,64}\b|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
    caseSensitive: false,
  );

  // Phone numbers pattern
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b',
  );

  // Passcodes & OTPs pattern (4-8 digit numbers)
  static final RegExp _otpRegex = RegExp(
    r'\b\d{4,8}\b',
  );

  /// Redacts sensitive PII tokens from the provided string.
  /// Returns empty string if [text] is null or empty.
  /// Fully protected by error handling to prevent runtime exceptions.
  static String redact(String? text) {
    if (text == null || text.isEmpty) {
      return '';
    }

    try {
      String result = text;

      // 1. Redact URLs first to avoid matching parts of URLs in other regexes
      result = result.replaceAll(_urlRegex, '[REDACTED_URL]');

      // 2. Redact Emails
      result = result.replaceAll(_emailRegex, '[REDACTED_EMAIL]');

      // 3. Redact Credit / Debit Card Numbers
      result = result.replaceAll(_cardRegex, '[REDACTED_CARD]');

      // 4. Redact Phone Numbers
      result = result.replaceAll(_phoneRegex, '[REDACTED_PHONE]');

      // 5. Redact Monetary Amounts
      result = result.replaceAll(_monetaryRegex, '[REDACTED_AMOUNT]');

      // 6. Redact Auth Tokens / JWTs / Bearer Tokens
      result = result.replaceAll(_tokenRegex, '[REDACTED_TOKEN]');

      // 7. Redact Passcodes / OTPs (standalone 4-8 digit numbers)
      result = result.replaceAll(_otpRegex, '[REDACTED_OTP]');

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PiiRedactor error during redaction: $e');
      }
      return '[REDACTED_ERROR]';
    }
  }

  /// Convenience wrapper for redacting notification titles.
  static String redactTitle(String? title) => redact(title);

  /// Convenience wrapper for redacting notification content.
  static String redactContent(String? content) => redact(content);

  /// Redacts sensitive string values inside a map recursively.
  static Map<String, dynamic> redactMap(Map<String, dynamic> data) {
    final Map<String, dynamic> redacted = {};
    data.forEach((key, value) {
      if (value is String) {
        redacted[key] = redact(value);
      } else if (value is Map<String, dynamic>) {
        redacted[key] = redactMap(value);
      } else if (value is List) {
        redacted[key] = redactList(value);
      } else {
        redacted[key] = value;
      }
    });
    return redacted;
  }

  /// Redacts sensitive string elements inside a list recursively.
  static List<dynamic> redactList(List<dynamic> list) {
    return list.map((item) {
      if (item is String) {
        return redact(item);
      } else if (item is Map<String, dynamic>) {
        return redactMap(item);
      } else if (item is List) {
        return redactList(item);
      }
      return item;
    }).toList();
  }
}
