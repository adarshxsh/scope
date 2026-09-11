class PiiRedactor {
  /// Redacts OTP code string (e.g., '987652' -> '••••56').
  static String redactOtp(String? otp) {
    if (otp == null || otp.isEmpty) return 'None';
    if (otp.length > 2) {
      final masked = '•' * (otp.length - 2);
      final visible = otp.substring(otp.length - 2);
      return '$masked$visible';
    }
    return '••••';
  }

  /// Redacts monetary value or amount string (e.g., '500' -> 'Rs. ••••', 'Rs. 500' -> 'Rs. ••••').
  static String redactAmount(dynamic amount) {
    if (amount == null) return 'None';
    final str = amount.toString().trim();
    if (str.isEmpty) return 'None';

    if (str.startsWith('Rs.')) {
      return 'Rs. ••••';
    } else if (str.startsWith('\$')) {
      return '\$••••';
    } else if (RegExp(r'^\d+(\.\d+)?$').hasMatch(str)) {
      return 'Rs. ••••';
    }
    return '••••';
  }

  /// Redacts email address (e.g., 'user@example.com' -> 'u•••@e••••.com' or '[user@example.com]' -> '[••••@••••.com]').
  static String redactEmail(String? email) {
    if (email == null || email.isEmpty) return 'None';
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    if (!emailRegex.hasMatch(email)) {
      return '••••';
    }
    return email.replaceAllMapped(emailRegex, (match) {
      final matched = match.group(0)!;
      final parts = matched.split('@');
      if (parts.length != 2) return '••••@••••.com';
      final local = parts[0];
      final domain = parts[1];

      final redactedLocal = local.isNotEmpty
          ? '${local[0]}${'•' * (local.length > 1 ? local.length - 1 : 3)}'
          : '••••';

      final domainParts = domain.split('.');
      final redactedDomainName = domainParts[0].isNotEmpty
          ? '${domainParts[0][0]}${'•' * (domainParts[0].length > 1 ? domainParts[0].length - 1 : 3)}'
          : '••••';
      final tld = domainParts.length > 1 ? domainParts.sublist(1).join('.') : 'com';

      return '$redactedLocal@$redactedDomainName.$tld';
    });
  }

  /// Redacts phone number (e.g., '+1234567890' -> '••••••7890').
  static String redactPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return 'None';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 4) {
      final maskedDigits = '•' * (digits.length - 4) + digits.substring(digits.length - 4);
      if (phone.startsWith('+')) {
        return '+$maskedDigits';
      }
      return maskedDigits;
    }
    return '••••';
  }

  /// Redacts URL / Hyperlink (e.g., 'https://example.com/path' -> 'https://••••').
  static String redactUrl(String? url) {
    if (url == null || url.isEmpty) return 'None';
    final urlRegex = RegExp(r'https?://[^\s,\]]+');
    if (urlRegex.hasMatch(url)) {
      return url.replaceAllMapped(urlRegex, (match) {
        final matched = match.group(0)!;
        if (matched.startsWith('https://')) {
          return 'https://••••';
        } else if (matched.startsWith('http://')) {
          return 'http://••••';
        }
        return 'https://••••';
      });
    }
    return '••••';
  }

  /// Redacts defining word / feature tag chips in post-mortem panel.
  /// Examples:
  /// 'OTP:987652' -> 'OTP:••••'
  /// 'Amount:Rs.500' -> 'Amount:Rs.••••'
  static String redactDefiningWord(String word) {
    if (word.startsWith('OTP:')) {
      return 'OTP:••••';
    }
    if (word.startsWith('Amount:')) {
      return 'Amount:Rs.••••';
    }
    if (word.startsWith('Email:') || word.startsWith('email:')) {
      return 'Email:••••';
    }
    if (word.startsWith('Phone:') || word.startsWith('phone:')) {
      return 'Phone:••••';
    }
    if (word.startsWith('URL:') || word.startsWith('url:')) {
      return 'URL:••••';
    }
    return word;
  }

  /// General text redactor to replace PII occurrences in free text.
  static String redactText(String text) {
    var result = text;
    // Emails
    result = redactEmail(result);
    // URLs
    result = redactUrl(result);
    // Phone numbers
    final phoneRegex = RegExp(r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b');
    result = result.replaceAllMapped(phoneRegex, (m) => redactPhoneNumber(m.group(0)));
    // OTPs (4-8 digit numbers standalone)
    final otpRegex = RegExp(r'\b\d{4,8}\b');
    result = result.replaceAllMapped(otpRegex, (m) => redactOtp(m.group(0)));
    // Amounts
    final amountRegex = RegExp(r'(?:Rs\.|₹|\$)\s*\d+(?:\.\d+)?');
    result = result.replaceAllMapped(amountRegex, (m) => redactAmount(m.group(0)));
    return result;
  }
}
