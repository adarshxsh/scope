/// Structured features extracted from raw notification text.
library;

class ExtractedFeatures {
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

  /// Creates features from a Map.
  factory ExtractedFeatures.fromMap(Map<String, dynamic> map) {
    return ExtractedFeatures(
      otp: map['otp'] as String?,
      amount: (map['amount'] as num?)?.toDouble(),
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
