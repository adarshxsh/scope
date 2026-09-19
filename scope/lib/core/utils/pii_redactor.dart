import 'package:flutter/foundation.dart';

/// Centralized utility for redacting sensitive PII (Personally Identifiable Information)
/// and authentication data in notification titles and content before writing to system logs or console output.
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
    r'https?://[^\s]+|www\.[^\s]+|\b(?:https?:\/\/|www\.)[^\s]+',
    caseSensitive: false,
  );

  // Monetary Amounts & Currency values pattern
  static final RegExp _monetaryRegex = RegExp(
    r'(?:[\$₹€£]|USD|INR|EUR|GBP|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?|\b[\d,]+(?:\.\d{1,2})?\s*(?:USD|INR|EUR|GBP|dollars|rupees|Rs\.?)\b',
    caseSensitive: false,
  );

  // JWT / Auth tokens / API Keys / Bearer tokens pattern
  static final RegExp _tokenRegex = RegExp(
    r'\b[A-Fa-f0-9]{32,64}\b|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b|(?:bearer|token|secret|key|auth)\s*[:=]?\s*([A-Za-z0-9._~+/-]{12,})',
    caseSensitive: false,
  );

  // Phone numbers pattern
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?(?:\d{3}[-.\s]?)?\d{4}\b',
    caseSensitive: false,
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

      // 1. Redact Auth Tokens / JWTs / Bearer Tokens
      result = result.replaceAllMapped(_tokenRegex, (match) {
        final matchedText = match.group(0) ?? '';
        final tokenGroup = match.groupCount >= 1 ? match.group(1) : null;
        if (tokenGroup != null && tokenGroup.isNotEmpty) {
          return matchedText.replaceFirst(tokenGroup, '[REDACTED_TOKEN]');
        }
        return '[REDACTED_TOKEN]';
      });

      // 2. Redact Email Addresses
      result = result.replaceAll(_emailRegex, '[REDACTED_EMAIL]');

      // 3. Redact URLs
      result = result.replaceAll(_urlRegex, '[REDACTED_URL]');

      // 4. Redact Credit / Debit Card Numbers (and validate digit count 13-19)
      result = result.replaceAllMapped(_cardRegex, (match) {
        final value = match.group(0) ?? '';
        final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
        if (digitsOnly.length >= 13 && digitsOnly.length <= 19) {
          return '[REDACTED_CARD]';
        }
        return value;
      });

      // 5. Redact Monetary Amounts
      result = result.replaceAll(_monetaryRegex, '[REDACTED_AMOUNT]');

      // 6. Redact Phone Numbers
      result = result.replaceAll(_phoneRegex, '[REDACTED_PHONE]');

      // 7. Redact Passcodes / OTPs (standalone 4-8 digit numbers, excluding 2020-2030 years)
      result = result.replaceAllMapped(_otpRegex, (match) {
        final value = match.group(0) ?? '';
        final val = int.tryParse(value);
        if (val != null && val >= 2020 && val <= 2030) {
          return value; // Keep year strings
        }
        return '[REDACTED_OTP]';
      });

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
}
