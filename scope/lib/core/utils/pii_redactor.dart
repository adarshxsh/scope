class PiiRedactor {
  PiiRedactor._();

  static final RegExp _emailRegExp = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _urlRegExp = RegExp(
    r'https?://[^\s]+|www\.[^\s]+',
    caseSensitive: false,
  );

  static final RegExp _phoneRegExp = RegExp(
    r'\+?\d{10,13}\b|\b\d{10}\b',
  );

  static final RegExp _monetaryRegExp = RegExp(
    r'(?:[₹$€£]\s?\d+(?:,\d+)*(?:\.\d+)?|\b(?:Rs\.?|INR|USD|EUR)\s?\d+(?:,\d+)*(?:\.\d+)?|\b\d+(?:,\d+)*(?:\.\d+)?\s?(?:INR|USD|EUR|Rs\.?)\b)',
    caseSensitive: false,
  );

  static final RegExp _otpRegExp = RegExp(
    r'\b\d{4,8}\b',
  );

  /// Redacts email addresses in [text].
  static String redactEmail(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_emailRegExp, '[REDACTED EMAIL]');
  }

  /// Redacts URLs in [text].
  static String redactUrl(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_urlRegExp, '[REDACTED URL]');
  }

  /// Redacts phone numbers in [text].
  static String redactPhone(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_phoneRegExp, '[REDACTED PHONE]');
  }

  /// Redacts monetary quantities in [text].
  static String redactMonetary(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_monetaryRegExp, '[REDACTED AMOUNT]');
  }

  /// Redacts isolated OTP numbers (4-8 digits) in [text].
  static String redactOtp(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_otpRegExp, '[REDACTED OTP]');
  }

  /// Sanitizes all identifiable PII in [text].
  static String redact(String text) {
    if (text.isEmpty) return text;
    var result = redactEmail(text);
    result = redactUrl(result);
    result = redactPhone(result);
    result = redactMonetary(result);
    result = redactOtp(result);
    return result;
  }

  /// Alias for [redact].
  static String mask(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    return redact(text);
  }

  /// Masks a string value completely if not null.
  static String maskValue(String? value, {String placeholder = '[REDACTED]'}) {
    if (value == null || value.isEmpty) return value ?? '';
    return placeholder;
  }

  /// Redacts sensitive fields in an extracted features map.
  static Map<String, dynamic> redactFeatures(Map<String, dynamic>? features) {
    if (features == null) return {};
    final map = Map<String, dynamic>.from(features);

    if (map.containsKey('otp') && map['otp'] != null) {
      map['otp'] = '[REDACTED OTP]';
    }
    if (map.containsKey('amount') && map['amount'] != null) {
      map['amount'] = '[REDACTED AMOUNT]';
    }
    if (map.containsKey('urls') && map['urls'] is List) {
      final list = map['urls'] as List;
      if (list.isNotEmpty) {
        map['urls'] = list.map((_) => '[REDACTED URL]').toList();
      }
    }
    if (map.containsKey('emails') && map['emails'] is List) {
      final list = map['emails'] as List;
      if (list.isNotEmpty) {
        map['emails'] = list.map((_) => '[REDACTED EMAIL]').toList();
      }
    }
    if (map.containsKey('phoneNumbers') && map['phoneNumbers'] is List) {
      final list = map['phoneNumbers'] as List;
      if (list.isNotEmpty) {
        map['phoneNumbers'] = list.map((_) => '[REDACTED PHONE]').toList();
      }
    }

    return map;
  }
}
