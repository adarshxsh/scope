/// Utility for redacting sensitive PII from log output and diagnostic displays.
class PiiRedactor {
  PiiRedactor._();

  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?(?:\d{3}[-.\s]?)?\d{4}\b',
    caseSensitive: false,
  );

  static final RegExp _urlRegex = RegExp(
    r'\b(?:https?:\/\/|www\.)[^\s]+',
    caseSensitive: false,
  );

  static final RegExp _creditCardRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  static final RegExp _otpRegex = RegExp(
    r'\b\d{4,8}\b',
  );

  static final RegExp _tokenRegex = RegExp(
    r'(?:bearer|token|secret|key|auth)\s*[:=]?\s*([A-Za-z0-9._~+/-]{12,})',
    caseSensitive: false,
  );

  /// Redacts sensitive PII fields from input string.
  static String redact(String input) {
    if (input.isEmpty) return input;

    String sanitized = input;

    // 1. Redact auth tokens
    sanitized = sanitized.replaceAllMapped(_tokenRegex, (match) {
      final matchedText = match.group(0) ?? '';
      final tokenValue = match.group(1) ?? '';
      if (tokenValue.isNotEmpty) {
        return matchedText.replaceFirst(tokenValue, '[REDACTED_TOKEN]');
      }
      return matchedText;
    });

    // 2. Redact emails
    sanitized = sanitized.replaceAll(_emailRegex, '[REDACTED_EMAIL]');

    // 3. Redact URLs
    sanitized = sanitized.replaceAll(_urlRegex, '[REDACTED_URL]');

    // 4. Redact Credit Cards (13-19 digits)
    sanitized = sanitized.replaceAllMapped(_creditCardRegex, (match) {
      final value = match.group(0) ?? '';
      final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.length >= 13 && digitsOnly.length <= 19) {
        return '[REDACTED_CARD]';
      }
      return value;
    });

    // 5. Redact Phone Numbers
    sanitized = sanitized.replaceAll(_phoneRegex, '[REDACTED_PHONE]');

    // 6. Redact 4-8 digit OTPs (excluding common 4-digit years like 2020-2030)
    sanitized = sanitized.replaceAllMapped(_otpRegex, (match) {
      final value = match.group(0) ?? '';
      final val = int.tryParse(value);
      if (val != null && val >= 2020 && val <= 2030) {
        return value; // Keep year strings
      }
      return '[REDACTED_OTP]';
    });

    return sanitized;
  }
}
