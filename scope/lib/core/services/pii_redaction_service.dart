/// Centralized PII Redaction Service for masking sensitive fields across UI components.
class PiiRedactionService {
  /// Mask OTP codes.
  /// Examples:
  /// - "882715" -> "••••15"
  /// - "352572" -> "••••72"
  /// - "1234" -> "••34"
  static String maskOtp(String? otp) {
    if (otp == null || otp.isEmpty) return 'None';
    final length = otp.length;
    if (length <= 2) {
      return '•' * length;
    }
    final unmasked = otp.substring(length - 2);
    final maskedDigits = '•' * (length - 2);
    return '$maskedDigits$unmasked';
  }

  /// Mask financial amount.
  /// Examples:
  /// - 5000.0 -> "₹••••.00"
  /// - 249.0 -> "₹••••.00"
  static String maskAmount(num? amount, {String currencyPrefix = '₹'}) {
    if (amount == null) return 'None';
    return '$currencyPrefix••••.00';
  }

  /// Mask amount string representation.
  /// Examples:
  /// - "Rs. 5000.0" -> "Rs. ••••.00"
  /// - "₹249" -> "₹••••.00"
  static String maskAmountString(String? amountStr) {
    if (amountStr == null || amountStr.isEmpty) return 'None';
    if (amountStr.contains('Rs.') || amountStr.contains('₹')) {
      final prefix = amountStr.contains('Rs.') ? 'Rs. ' : '₹';
      return '$prefix••••.00';
    }
    return '••••.00';
  }

  /// Mask Email address.
  /// Example:
  /// - "user@domain.com" -> "u***@domain.com"
  /// - "harsh16@example.com" -> "h***@example.com"
  static String maskEmail(String? email) {
    if (email == null || email.isEmpty) return 'None';
    final parts = email.split('@');
    if (parts.length != 2) return '••••@••••';
    final username = parts[0];
    final domain = parts[1];
    if (username.isEmpty) return '***@$domain';
    final firstChar = username[0];
    return '$firstChar***@$domain';
  }

  /// Mask Phone Number.
  /// Examples:
  /// - "9876543210" -> "••••••••10"
  /// - "+91 98765 43210" -> "••••••••10"
  static String maskPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return 'None';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 2) return '••••';
    final last2 = digits.substring(digits.length - 2);
    return '••••••••$last2';
  }

  /// Mask URLs with query parameters.
  /// Example:
  /// - "https://example.com/reset?token=xyz" -> "https://example.com/reset?••••"
  static String maskUrl(String? url) {
    if (url == null || url.isEmpty) return 'None';
    if (url.contains('?')) {
      final baseUrl = url.split('?').first;
      return '$baseUrl?••••';
    }
    return url;
  }

  /// Mask a list of URLs.
  static String maskUrls(List? urls) {
    if (urls == null || urls.isEmpty) return 'None';
    final masked = urls.map((u) => maskUrl(u.toString())).toList();
    return masked.toString();
  }

  /// Mask a list of Emails.
  static String maskEmails(List? emails) {
    if (emails == null || emails.isEmpty) return 'None';
    final masked = emails.map((e) => maskEmail(e.toString())).toList();
    return masked.toString();
  }

  /// Mask a list of Phone Numbers.
  static String maskPhoneNumbers(List? phones) {
    if (phones == null || phones.isEmpty) return 'None';
    final masked = phones.map((p) => maskPhoneNumber(p.toString())).toList();
    return masked.toString();
  }

  /// Redact all sensitive PII pattern occurrences in general text.
  static String redactText(String text) {
    if (text.isEmpty) return text;
    var result = text;

    // Redact verification code / OTP numbers in text
    result = result.replaceAllMapped(
      RegExp(r'\b(OTP|code|verification|pin|password|2fa)\b(\s+(?:code|is|number|:|-)?\s*)(\d{4,8})\b', caseSensitive: false),
      (m) {
        final prefix = m.group(1)!;
        final gap = m.group(2)!;
        final code = m.group(3)!;
        return '$prefix$gap${maskOtp(code)}';
      },
    );


    // Redact monetary values in text e.g. Rs. 5000 / ₹5000 / Rs. 5000.00
    result = result.replaceAllMapped(
      RegExp(r'(?:Rs\.?|₹)\s*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      (m) => 'Rs. ••••.00',
    );

    // Redact Emails in text
    result = result.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
      (m) => maskEmail(m.group(0)),
    );

    // Redact URLs with query parameters in text
    result = result.replaceAllMapped(
      RegExp(r'https?://[^\s]+\?[^\s]+'),
      (m) => maskUrl(m.group(0)),
    );

    return result;
  }
}
