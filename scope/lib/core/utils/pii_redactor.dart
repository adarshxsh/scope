class PiiRedactor {
  PiiRedactor._();

  static const String redactedOtp = '[REDACTED_OTP]';
  static const String redactedAmount = '[REDACTED_AMOUNT]';
  static const String redactedUrl = '[REDACTED_URL]';
  static const String redactedEmail = '[REDACTED_EMAIL]';
  static const String redactedPhone = '[REDACTED_PHONE]';

  static final RegExp _otpRegex = RegExp(
    r'(?:\b(?:otp|code|pin|passcode)\b|verification\s*code)[^\d]{0,15}?([0-9]{4,8})\b',
    caseSensitive: false,
  );

  static final RegExp _currencyRegex = RegExp(
    r'(?:rs\.?|inr|usd|\$|€|₹|eur)\s*\d+(?:,\d+)*(?:\.\d{1,2})?',
    caseSensitive: false,
  );

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s/$.?#].[^\s]*|www\.[^\s]+',
    caseSensitive: false,
  );

  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  static final RegExp _phoneRegex = RegExp(
    r'(?:\+?\d{1,3}[\s.-]?)?\(?\d{2,4}\)?[\s.-]?\d{3,4}[\s.-]?\d{3,4}',
  );

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

  /// Sanitizes raw text string by substituting PII patterns with redacted tags.
  static String redactText(String? input) {
    if (input == null || input.isEmpty) return '';

    String result = input;

    // 1. Redact explicit OTP phrases
    result = result.replaceAllMapped(_otpRegex, (match) {
      final fullMatch = match.group(0) ?? '';
      final digits = match.group(1) ?? '';
      return fullMatch.replaceFirst(digits, redactedOtp);
    });

    // 2. Redact Currency / Amounts
    result = result.replaceAll(_currencyRegex, redactedAmount);

    // 3. Redact URLs
    result = result.replaceAll(_urlRegex, redactedUrl);

    // 4. Redact Emails
    result = result.replaceAll(_emailRegex, redactedEmail);

    // 5. Redact Phone Numbers
    result = result.replaceAll(_phoneRegex, redactedPhone);

    return result;
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
