import 'package:flutter/foundation.dart';

/// Centralized utility for redacting sensitive PII (Personally Identifiable Information)
/// and authentication data in notification titles, content, database models, and UI screens.
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
    r'\b(?:https?:\/\/|www\.)[^\s]+|\b[A-Za-z0-9.-]+\.(?:com|org|net|in|io|dev|app|co)\b',
    caseSensitive: false,
  );

  // Monetary Amounts & Currency values pattern for logcat redaction
  static final RegExp _monetaryRegex = RegExp(
    r'(?:[\$₹€£]|USD|INR|EUR|GBP|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?|\b[\d,]+(?:\.\d{1,2})?\s*(?:USD|INR|EUR|GBP|dollars|rupees|Rs\.?)\b',
    caseSensitive: false,
  );

  // Monetary Amounts pattern for UI maskText
  static final RegExp _amountRegex = RegExp(
    r'(?:₹|rs\.?|inr|usd|\$|eur|€|gbp|£|aed)\s*([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)|([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|usd|eur|gbp|aed)',
    caseSensitive: false,
  );

  // JWT / Auth tokens / API Keys pattern
  static final RegExp _tokenRegex = RegExp(
    r'\b[A-Fa-f0-9]{32,64}\b|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );

  // Phone numbers pattern
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+\d{1,3}[- ]?)?\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}\b|\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b',
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

  /// Redacts sensitive fields in the `extractedFeatures` map before SQL encoding.
  static Map<String, dynamic> redactFeaturesMap(Map<String, dynamic> map) {
    final copy = Map<String, dynamic>.from(map);

    if (copy.containsKey('otp') && copy['otp'] != null) {
      final rawOtp = copy['otp'].toString();
      copy['otp'] = maskOtp(rawOtp);
    }

    if (copy.containsKey('amount') && copy['amount'] != null) {
      copy['amount'] = null;
    }

    if (copy.containsKey('urls') && copy['urls'] is Iterable) {
      copy['urls'] = (copy['urls'] as Iterable)
          .map((u) => maskUrl(u?.toString()))
          .whereType<String>()
          .toList();
    }

    if (copy.containsKey('emails') && copy['emails'] is Iterable) {
      copy['emails'] = (copy['emails'] as Iterable)
          .map((e) => maskEmail(e?.toString()))
          .whereType<String>()
          .toList();
    }

    if (copy.containsKey('phoneNumbers') && copy['phoneNumbers'] is Iterable) {
      copy['phoneNumbers'] = (copy['phoneNumbers'] as Iterable)
          .map((p) => maskPhoneNumber(p?.toString()))
          .whereType<String>()
          .toList();
    }

    return copy;
  }

  /// Masks an OTP security code.
  static String maskOtp(String? otp) {
    if (otp == null || otp.isEmpty) return '[REDACTED OTP]';
    return '[REDACTED OTP]';
  }

  /// Masks a transaction monetary amount.
  static String maskAmount(dynamic amount) {
    if (amount == null) return 'Rs. [HIDDEN]';
    return 'Rs. [HIDDEN]';
  }

  /// Masks an email address.
  static String maskEmail(String? email) {
    if (email == null || email.isEmpty) return '[REDACTED EMAIL]';
    return '[REDACTED EMAIL]';
  }

  /// Masks a phone number.
  static String maskPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return '[REDACTED PHONE]';
    return '[REDACTED PHONE]';
  }

  /// Masks a URL.
  static String maskUrl(String? url) {
    if (url == null || url.isEmpty) return '[REDACTED URL]';
    return '[REDACTED URL]';
  }

  /// Redacts inline PII patterns in raw text snippets, content, and traces.
  static String maskText(String text) {
    if (text.isEmpty) return text;

    String masked = text;

    // 1. Emails
    masked = masked.replaceAllMapped(_emailRegex, (_) => '[REDACTED EMAIL]');

    // 2. URLs
    masked = masked.replaceAllMapped(_urlRegex, (_) => '[REDACTED URL]');

    // 3. Amounts (e.g., Rs. 500, $20, ₹1000)
    masked = masked.replaceAllMapped(_amountRegex, (match) {
      return 'Rs. [HIDDEN]';
    });

    // 4. Phone numbers
    masked = masked.replaceAllMapped(_phoneRegex, (_) => '[REDACTED PHONE]');

    // 5. OTPs - numbers in OTP context or 4-8 digit standalone numbers
    final lower = masked.toLowerCase();
    if (lower.contains('otp') ||
        lower.contains('verification') ||
        lower.contains('code') ||
        lower.contains('verify') ||
        lower.contains('password') ||
        lower.contains('pin')) {
      masked = masked.replaceAllMapped(_otpRegex, (match) {
        final val = match.group(0)!;
        final numVal = int.tryParse(val);
        // Exclude year-like digits unless context is strictly OTP
        if (numVal != null && numVal >= 2020 && numVal <= 2030) {
          return val;
        }
        return '[REDACTED OTP]';
      });
    }

    return masked;
  }
}
