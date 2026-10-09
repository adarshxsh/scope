/// Structured features extracted from raw notification text.
library;

class ExtractedFeatures {
  /// Standard static redaction tokens.
  static const String redactedOtp = '[REDACTED_OTP]';
  static const String redactedAmount = '[REDACTED_AMOUNT]';
  static const String redactedUrl = '[REDACTED_URL]';
  static const String redactedEmail = '[REDACTED_EMAIL]';
  static const String redactedPhone = '[REDACTED_PHONE]';

  /// Extracted OTP security code (4 to 8 digits).
  final String? otp;

  /// Extracted currency transaction amount.
  final double? amount;

  /// Whether the notification contains indicators of a deadline.
  final bool hasDeadline;

  /// List of hyperlinks extracted.
  final List<String> urls;

  /// List of email addresses extracted.
  final List<String> emails;

  /// List of phone numbers extracted.
  final List<String> phoneNumbers;

  const ExtractedFeatures({
    this.otp,
    this.amount,
    this.hasDeadline = false,
    this.urls = const [],
    this.emails = const [],
    this.phoneNumbers = const [],
  });

  /// Creates features from a Map, safely handling both raw and redacted values.
  factory ExtractedFeatures.fromMap(Map<String, dynamic> map) {
    double? parsedAmount;
    final rawAmount = map['amount'];
    if (rawAmount is num) {
      parsedAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      parsedAmount = double.tryParse(rawAmount);
    }

    return ExtractedFeatures(
      otp: map['otp'] as String?,
      amount: parsedAmount,
      hasDeadline: map['hasDeadline'] as bool? ?? false,
      urls: List<String>.from(map['urls'] as Iterable? ?? const []),
      emails: List<String>.from(map['emails'] as Iterable? ?? const []),
      phoneNumbers: List<String>.from(map['phoneNumbers'] as Iterable? ?? const []),
    );
  }

  /// Converts features to a Map.
  Map<String, dynamic> toMap() {
    return {
      'otp': otp,
      'amount': amount,
      'hasDeadline': hasDeadline,
      'urls': urls,
      'emails': emails,
      'phoneNumbers': phoneNumbers,
    };
  }

  /// Converts features to a Map with static PII redaction tokens.
  Map<String, dynamic> toRedactedMap() {
    return {
      'otp': otp != null && otp!.isNotEmpty ? redactedOtp : null,
      'amount': amount != null ? redactedAmount : null,
      'hasDeadline': hasDeadline,
      'urls': urls.map((_) => redactedUrl).toList(),
      'emails': emails.map((_) => redactedEmail).toList(),
      'phoneNumbers': phoneNumbers.map((_) => redactedPhone).toList(),
    };
  }

  /// Static helper to replace sensitive PII values in a features map with static tokens,
  /// preserving existing JSON schema keys.
  static Map<String, dynamic>? redactMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final result = Map<String, dynamic>.from(map);

    if (result.containsKey('otp') && result['otp'] != null && result['otp'].toString().isNotEmpty) {
      result['otp'] = redactedOtp;
    }

    if (result.containsKey('amount') && result['amount'] != null) {
      result['amount'] = redactedAmount;
    }

    if (result.containsKey('urls') && result['urls'] is Iterable) {
      final list = List.from(result['urls'] as Iterable);
      if (list.isNotEmpty) {
        result['urls'] = list.map((_) => redactedUrl).toList();
      }
    }

    if (result.containsKey('emails') && result['emails'] is Iterable) {
      final list = List.from(result['emails'] as Iterable);
      if (list.isNotEmpty) {
        result['emails'] = list.map((_) => redactedEmail).toList();
      }
    }

    if (result.containsKey('phoneNumbers') && result['phoneNumbers'] is Iterable) {
      final list = List.from(result['phoneNumbers'] as Iterable);
      if (list.isNotEmpty) {
        result['phoneNumbers'] = list.map((_) => redactedPhone).toList();
      }
    }

    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExtractedFeatures &&
        other.otp == otp &&
        other.amount == amount &&
        other.hasDeadline == hasDeadline &&
        _listsEqual(other.urls, urls) &&
        _listsEqual(other.emails, emails) &&
        _listsEqual(other.phoneNumbers, phoneNumbers);
  }

  static bool _listsEqual(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        otp,
        amount,
        hasDeadline,
        Object.hashAll(urls),
        Object.hashAll(emails),
        Object.hashAll(phoneNumbers),
      );

  @override
  String toString() {
    return 'ExtractedFeatures(otp: $otp, amount: $amount, hasDeadline: $hasDeadline, '
        'urls: $urls, emails: $emails, phoneNumbers: $phoneNumbers)';
  }
}
