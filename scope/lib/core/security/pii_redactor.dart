/// Standardized PII masking utility for OTPs, financial amounts, URLs, emails, and phone numbers.
class PiiRedactor {
  static const String maskChar = '*';

  /// Masks OTP codes (preserves last 2 digits for recognition).
  /// Example: '882715' -> '****15', '34' -> '**', '1234' -> '**34'
  static String maskOtp(String? otp) {
    if (otp == null || otp.trim().isEmpty) return 'None';
    final clean = otp.trim();
    if (clean.length <= 2) {
      return maskChar * clean.length;
    }
    final maskedPart = maskChar * (clean.length - 2);
    final visiblePart = clean.substring(clean.length - 2);
    return '$maskedPart$visiblePart';
  }

  /// Masks financial transaction amounts.
  /// Example: '5000' -> '$***.00', 'Rs. 5000' -> 'Rs. ***0', 799 -> '₹***'
  static String maskAmount(dynamic amount) {
    if (amount == null) return 'None';
    final str = amount.toString().trim();
    if (str.isEmpty) return 'None';

    if (str.startsWith('Rs.') || str.startsWith('Rs') || str.startsWith('INR')) {
      final digits = str.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return 'Rs. ***.00';
      final lastDigit = digits.isNotEmpty ? digits[digits.length - 1] : '0';
      return 'Rs. ***$lastDigit';
    } else if (str.startsWith('₹')) {
      final digits = str.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return '₹***.00';
      final lastDigit = digits.isNotEmpty ? digits[digits.length - 1] : '0';
      return '₹***$lastDigit';
    } else if (str.startsWith('\$')) {
      return '\$***.00';
    } else {
      // Pure number or unformatted amount
      final numVal = double.tryParse(str);
      if (numVal != null) {
        return '\$***.00';
      }
      final digits = str.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        final last = digits[digits.length - 1];
        return '\$***.$last';
      }
      return '\$***.00';
    }
  }

  static String get _last0 => '0';

  /// Masks URLs.
  /// Example: 'https://example.com/auth?token=123' -> 'https://***'
  static String maskUrl(String? url) {
    if (url == null || url.trim().isEmpty) return 'None';
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri != null && uri.hasScheme) {
      return '${uri.scheme}://***';
    }
    return 'http://***';
  }

  /// Masks email addresses.
  /// Example: 'harsh16@example.com' -> 'h***6@example.com'
  static String maskEmail(String? email) {
    if (email == null || email.trim().isEmpty) return 'None';
    final clean = email.trim();
    final parts = clean.split('@');
    if (parts.length != 2) return '***@***.com';

    final name = parts[0];
    final domain = parts[1];

    String maskedName;
    if (name.length <= 2) {
      maskedName = maskChar * name.length;
    } else {
      maskedName = '${name[0]}${maskChar * (name.length - 2)}${name[name.length - 1]}';
    }

    return '$maskedName@$domain';
  }

  /// Masks phone numbers (preserves last 4 digits).
  /// Example: '+1 555-123-4567' -> '***-***-4567', '9876543210' -> '******3210'
  static String maskPhoneNumber(String? phone) {
    if (phone == null || phone.trim().isEmpty) return 'None';
    final clean = phone.trim();
    final digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) {
      return maskChar * clean.length;
    }
    final last4 = digits.substring(digits.length - 4);
    if (clean.contains('-')) {
      return '***-***-$last4';
    }
    return '${maskChar * (digits.length - 4)}$last4';
  }

  /// Replaces detected PII instances in a full string with masked equivalents.
  static String redactText(String? text) {
    if (text == null || text.isEmpty) return '';

    String result = text;

    // Mask Emails
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    result = result.replaceAllMapped(emailRegex, (m) => maskEmail(m.group(0)));

    // Mask URLs
    final urlRegex = RegExp(r'https?://[^\s]+');
    result = result.replaceAllMapped(urlRegex, (m) => maskUrl(m.group(0)));

    // Mask Phone numbers
    final phoneRegex = RegExp(r'(\+\d{1,3}\s?)?(\(?\d{3}\)?[\s.-]?)?\d{3}[\s.-]?\d{4}');
    result = result.replaceAllMapped(phoneRegex, (m) => maskPhoneNumber(m.group(0)));

    return result;
  }
}
