import 'package:flutter/foundation.dart';

/// Centralized utility for redacting sensitive PII (Personally Identifiable Information)
/// and authentication data in notification titles, content, UI, and system logs.
class PiiRedactor {
  PiiRedactor._();

  static const String redactedOtp = '[REDACTED_OTP]';
  static const String redactedAmount = '[REDACTED_AMOUNT]';
  static const String redactedUrl = '[REDACTED_URL]';
  static const String redactedEmail = '[REDACTED_EMAIL]';
  static const String redactedPhone = '[REDACTED_PHONE]';
  static const String redactedCard = '[REDACTED_CARD]';
  static const String redactedToken = '[REDACTED_TOKEN]';

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

  // JWT / Auth tokens / API Keys pattern
  static final RegExp _tokenRegex = RegExp(
    r'\b[A-Fa-f0-9]{32,64}\b|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );

  // Phone numbers pattern
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+\d{1,3}[- ]?)?\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}\b',
  );

  // Passcodes & OTPs pattern
  static final RegExp _otpPhraseRegex = RegExp(
    r'(?:\b(?:otp|code|pin|passcode)\b|verification\s*code)[^\d]{0,15}?([0-9]{4,8})\b',
    caseSensitive: false,
  );

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
      result = result.replaceAll(_cardRegex, redactedCard);

      // 2. Redact Email Addresses
      result = result.replaceAll(_emailRegex, redactedEmail);

      // 3. Redact URLs
      result = result.replaceAll(_urlRegex, redactedUrl);

      // 4. Redact Monetary Amounts
      result = result.replaceAll(_monetaryRegex, redactedAmount);

      // 5. Redact Auth Tokens / JWTs
      result = result.replaceAll(_tokenRegex, redactedToken);

      // 6. Redact Phone Numbers
      result = result.replaceAll(_phoneRegex, redactedPhone);

      // 7. Redact Passcodes / OTPs
      result = result.replaceAllMapped(_otpPhraseRegex, (match) {
        final fullMatch = match.group(0) ?? '';
        final digits = match.group(1) ?? '';
        return fullMatch.replaceFirst(digits, redactedOtp);
      });
      result = result.replaceAll(_otpRegex, redactedOtp);

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PiiRedactor error during redaction: $e');
      }
      return '[REDACTED_ERROR]';
    }
  }

  /// Alias for redact.
  static String redactText(String? input) => redact(input);

  /// Convenience wrapper for redacting notification titles.
  static String redactTitle(String? title) => redact(title);

  /// Convenience wrapper for redacting notification content.
  static String redactContent(String? content) => redact(content);

  /// Redacts OTP code if provided.
  static String? redactOtp(String? otp) {
    if (otp == null || otp.isEmpty) return null;
    return redactedOtp;
  }

  /// Redacts transaction amount if provided.
  static String? redactAmount(dynamic amount) {
    if (amount == null) return null;
    return redactedAmount;
  }

  /// Redacts URL string or list of URLs.
  static String? redactUrl(dynamic url) {
    if (url == null) return null;
    if (url is List && url.isEmpty) return null;
    return redactedUrl;
  }

  /// Redacts Email string or list of Emails.
  static String? redactEmail(dynamic email) {
    if (email == null) return null;
    if (email is List && email.isEmpty) return null;
    return redactedEmail;
  }

  /// Redacts Phone Number string or list of Phone Numbers.
  static String? redactPhone(dynamic phone) {
    if (phone == null) return null;
    if (phone is List && phone.isEmpty) return null;
    return redactedPhone;
  }

  /// Sanitizes an extracted features map, masking sensitive fields.
  static Map<String, dynamic> redactMap(Map<String, dynamic>? features) {
    if (features == null || features.isEmpty) return {};

    final redacted = Map<String, dynamic>.from(features);

    if (redacted.containsKey('otp') && redacted['otp'] != null) {
      redacted['otp'] = redactedOtp;
    }

    if (redacted.containsKey('amount') && redacted['amount'] != null) {
      redacted['amount'] = redactedAmount;
    }

    if (redacted.containsKey('urls') && redacted['urls'] is List && (redacted['urls'] as List).isNotEmpty) {
      redacted['urls'] = [(redacted['urls'] as List).length == 1 ? redactedUrl : '$redactedUrl x${(redacted['urls'] as List).length}'];
    }

    if (redacted.containsKey('emails') && redacted['emails'] is List && (redacted['emails'] as List).isNotEmpty) {
      redacted['emails'] = [(redacted['emails'] as List).length == 1 ? redactedEmail : '$redactedEmail x${(redacted['emails'] as List).length}'];
    }

    if (redacted.containsKey('phoneNumbers') && redacted['phoneNumbers'] is List && (redacted['phoneNumbers'] as List).isNotEmpty) {
      redacted['phoneNumbers'] = [(redacted['phoneNumbers'] as List).length == 1 ? redactedPhone : '$redactedPhone x${(redacted['phoneNumbers'] as List).length}'];
    }

    return redacted;
  }
}
