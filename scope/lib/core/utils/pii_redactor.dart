import 'package:flutter/foundation.dart';

/// Centralized utility for redacting sensitive PII (Personally Identifiable Information)
/// and authentication data in notification titles, content, and features maps.
class PiiRedactor {
  PiiRedactor._();

  // Credit/Debit Card pattern (13 to 19 digits, optional spaces/dashes)
  static final RegExp _cardRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  // Email Address pattern
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
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

  // JWT / Auth tokens / API Keys pattern
  static final RegExp _tokenRegex = RegExp(
    r'\b[A-Fa-f0-9]{32,64}\b|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );

  // Phone numbers pattern
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+\d{1,3}[- ]?)?\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}\b|\+?\d{10,13}\b|\b\d{10}\b',
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

      // 1. Redact Credit / Debit Card Numbers
      result = result.replaceAll(_cardRegex, '[REDACTED_CARD]');

      // 2. Redact Email Addresses
      result = result.replaceAll(_emailRegex, '[REDACTED_EMAIL]');

      // 3. Redact URLs
      result = result.replaceAll(_urlRegex, '[REDACTED_URL]');

      // 4. Redact Monetary Amounts
      result = result.replaceAll(_monetaryRegex, '[REDACTED_AMOUNT]');

      // 5. Redact Auth Tokens / JWTs
      result = result.replaceAll(_tokenRegex, '[REDACTED_TOKEN]');

      // 6. Redact Phone Numbers
      result = result.replaceAll(_phoneRegex, '[REDACTED_PHONE]');

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

  /// Alias for [redact].
  static String mask(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    return redact(text);
  }

  /// Masks a string value completely if not null.
  static String maskValue(String? value, {String placeholder = '[REDACTED]'}) {
    if (value == null || value.isEmpty) return value ?? '';
    return placeholder;
  }

  /// Redacts email addresses in [text].
  static String redactEmail(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_emailRegex, '[REDACTED EMAIL]');
  }

  /// Redacts URLs in [text].
  static String redactUrl(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_urlRegex, '[REDACTED URL]');
  }

  /// Redacts phone numbers in [text].
  static String redactPhone(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_phoneRegex, '[REDACTED PHONE]');
  }

  /// Redacts monetary quantities in [text].
  static String redactMonetary(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_monetaryRegex, '[REDACTED AMOUNT]');
  }

  /// Redacts isolated OTP numbers (4-8 digits) in [text].
  static String redactOtp(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_otpRegex, '[REDACTED OTP]');
  }

  /// Redacts sensitive fields in an extracted features map.
  static Map<String, dynamic> redactFeatures(Map<String, dynamic>? features) {
    if (features == null) return {};
    final map = Map<String, dynamic>.from(features);

    if (map.containsKey('otp') && map['otp'] != null) {
      map['otp'] = '[REDACTED OTP]';
    }
    if (map.containsKey('amount') && map['amount'] != null) {
      map['amount'] = '[REDACTED AMOUNT]';
    }
    if (map.containsKey('urls') && map['urls'] is List) {
      final list = map['urls'] as List;
      if (list.isNotEmpty) {
        map['urls'] = list.map((_) => '[REDACTED URL]').toList();
      }
    }
    if (map.containsKey('emails') && map['emails'] is List) {
      final list = map['emails'] as List;
      if (list.isNotEmpty) {
        map['emails'] = list.map((_) => '[REDACTED EMAIL]').toList();
      }
    }
    if (map.containsKey('phoneNumbers') && map['phoneNumbers'] is List) {
      final list = map['phoneNumbers'] as List;
      if (list.isNotEmpty) {
        map['phoneNumbers'] = list.map((_) => '[REDACTED PHONE]').toList();
      }
    }

    return map;
  }
}
