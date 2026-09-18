/// Centralized PII redactor utility to sanitize sensitive values in notification text,
/// diagnostic logs, and telemetry data before persistence or UI rendering.
abstract final class PiiRedactor {
  // Regex patterns for sensitive data extraction
  static final RegExp _emailRegExp = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _urlRegExp = RegExp(
    r'https?:\/\/[^\s]+|www\.[^\s]+',
    caseSensitive: false,
  );

  static final RegExp _phoneRegExp = RegExp(
    r'(\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}',
  );

  static final RegExp _creditCardRegExp = RegExp(
    r'\b(?:\d[ -]*?){13,16}\b',
  );

  static final RegExp _otpRegExp = RegExp(
    r'\b(?:otp|code|pin|passcode|verification|auth|password)\b[^\d]{0,15}?(\d{4,8})\b|\b(\d{4,8})\b(?=[^\d]{0,15}\b(?:otp|code|pin|verify)\b)',
    caseSensitive: false,
  );


  static final RegExp _amountRegExp = RegExp(
    r'(\$|₹|€|£|USD|INR|EUR|GBP)[\s]*\d+(?:,\d{3})*(?:\.\d{1,2})?|\b\d+(?:\.\d{1,2})?[\s]*(?:USD|INR|EUR|GBP)\b',
    caseSensitive: false,
  );

  static final RegExp _tokenRegExp = RegExp(
    r'bearer\s+[a-zA-Z0-9\-\._~\+\/]+=*|[a-f0-9]{32,64}',
    caseSensitive: false,
  );

  /// Sanitizes text by stripping emails, URLs, phone numbers, OTPs, amounts, tokens, and credit cards.
  static String redact(String? text) {
    if (text == null || text.isEmpty) {
      return text ?? '';
    }

    String result = text;

    // Redact URLs first to avoid matching parts of URLs in other regexes
    result = result.replaceAll(_urlRegExp, '[REDACTED_URL]');

    // Redact Emails
    result = result.replaceAll(_emailRegExp, '[REDACTED_EMAIL]');

    // Redact Credit Cards
    result = result.replaceAll(_creditCardRegExp, '[REDACTED_CARD]');

    // Redact Phone Numbers
    result = result.replaceAll(_phoneRegExp, '[REDACTED_PHONE]');

    // Redact Monetary Amounts
    result = result.replaceAll(_amountRegExp, '[REDACTED_AMOUNT]');

    // Redact OTPs
    result = result.replaceAllMapped(_otpRegExp, (match) {
      final fullMatch = match.group(0) ?? '';
      final digitPart = match.group(1) ?? match.group(2);
      if (digitPart != null) {
        return fullMatch.replaceFirst(digitPart, '[REDACTED_OTP]');
      }
      return '[REDACTED_OTP]';
    });


    // Redact Tokens / Keys
    result = result.replaceAll(_tokenRegExp, '[REDACTED_TOKEN]');

    return result;
  }

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
