/// Centralized PII redactor providing regex-based sanitization for sensitive
/// user data, such as authentication tokens, URLs, emails, phone numbers,
/// monetary values, and OTP passcodes in notification titles and content.
class PiiRedactor {
  static final RegExp _tokenRegExp = RegExp(
    r'\b(Bearer\s+[A-Za-z0-9._~+/-]+=*|[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})\b',
    caseSensitive: false,
  );

  static final RegExp _urlRegExp = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  static final RegExp _emailRegExp = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _phoneRegExp = RegExp(
    r'(?:\+\d{1,3}[\s-]?)?\(?\d{3}\)?[\s-]?\d{3}[\s-]?\d{4}\b',
  );

  static final RegExp _moneyRegExp = RegExp(
    r'(?:\$|₹|€|£|USD|INR|EUR|GBP)\s?\d+(?:,\d{3})*(?:\.\d{1,2})?',
    caseSensitive: false,
  );

  static final RegExp _otpRegExp = RegExp(
    r'\b\d{4,8}\b',
  );

  /// Sanitizes sensitive PII from [text] for logging and telemetry verification.
  /// Returns empty string if [text] is null or empty.
  static String redact(String? text) {
    if (text == null || text.isEmpty) return '';

    var sanitized = text;
    sanitized = sanitized.replaceAll(_tokenRegExp, '[REDACTED_TOKEN]');
    sanitized = sanitized.replaceAll(_urlRegExp, '[REDACTED_URL]');
    sanitized = sanitized.replaceAll(_emailRegExp, '[REDACTED_EMAIL]');
    sanitized = sanitized.replaceAll(_phoneRegExp, '[REDACTED_PHONE]');
    sanitized = sanitized.replaceAll(_moneyRegExp, '[REDACTED_MONEY]');
    sanitized = sanitized.replaceAll(_otpRegExp, '[REDACTED_OTP]');

    return sanitized;
  }
}
