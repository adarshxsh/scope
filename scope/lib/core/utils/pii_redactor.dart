/// Utility class providing regex sanitization and redaction for sensitive fields (OTPs, amounts, emails, phones, URLs).
class PiiRedactor {
  static final RegExp _otpRegExp = RegExp(r'\b\d{4,8}\b');
  static final RegExp _emailRegExp = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');
  static final RegExp _phoneRegExp = RegExp(r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b');
  static final RegExp _amountRegExp = RegExp(r'(?:Rs\.?|INR|USD|\$|₹)\s*\d+(?:,\d+)*(?:\.\d+)?', caseSensitive: false);
  static final RegExp _urlRegExp = RegExp(r'https?://[^\s]+');

  /// Redacts sensitive details from raw input text.
  static String redact(String text) {
    if (text.isEmpty) return text;

    String sanitized = text;
    sanitized = sanitized.replaceAll(_urlRegExp, '[REDACTED_URL]');
    sanitized = sanitized.replaceAll(_emailRegExp, '[REDACTED_EMAIL]');
    sanitized = sanitized.replaceAll(_amountRegExp, '[REDACTED_AMOUNT]');
    sanitized = sanitized.replaceAll(_phoneRegExp, '[REDACTED_PHONE]');

    // Replace standalone OTP numbers if context contains security/verification keywords
    final lower = text.toLowerCase();
    if (lower.contains('code') ||
        lower.contains('otp') ||
        lower.contains('verification') ||
        lower.contains('password') ||
        lower.contains('pin') ||
        lower.contains('auth')) {
      sanitized = sanitized.replaceAll(_otpRegExp, '[REDACTED_OTP]');
    }

    return sanitized;
  }
}
