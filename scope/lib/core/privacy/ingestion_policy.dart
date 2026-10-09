import 'package:scope/core/models/notification_model.dart';

/// User-configured pre-ingestion privacy policy.
///
/// Controls which notifications are ingested, filtered, or sanitized
/// before reaching persistent storage or AI analysis pipelines.
class IngestionPolicy {
  final Set<String> blockedPackages;
  final Set<String> excludedCategories;
  final bool otpMaskingEnabled;
  final bool financialProtectionEnabled;
  final bool blockSystemNoise;

  const IngestionPolicy({
    this.blockedPackages = const {},
    this.excludedCategories = const {},
    this.otpMaskingEnabled = true,
    this.financialProtectionEnabled = false,
    this.blockSystemNoise = true,
  });

  /// Default baseline policy protecting privacy without breaking core app functions.
  factory IngestionPolicy.defaultPolicy() {
    return const IngestionPolicy(
      blockedPackages: {},
      excludedCategories: {},
      otpMaskingEnabled: true,
      financialProtectionEnabled: false,
      blockSystemNoise: true,
    );
  }

  static final _otpDigitRegex = RegExp(r'\b\d{4,8}\b');
  static final _otpContextRegex = RegExp(
    r'\b(otp|code|verification|verify|v-code|pin|password|passcode|auth|secret|one-time|one time)\b',
    caseSensitive: false,
  );

  static final _systemNoiseCategories = {
    'sys',
    'system',
    'progress',
    'navigation',
    'service',
    'transport',
    'status',
  };

  static final _financeKeywords = {
    'bank',
    'debit',
    'credit',
    'card',
    'account',
    'balance',
    'transaction',
    'paid',
    'payment',
    'upi',
    'transfer',
    'withdrawal',
    'rs',
    'inr',
    '₹',
    '\$',
  };

  /// Redacts explicit OTP digits in text if OTP context keywords are present.
  static String maskOtpText(String text) {
    if (text.isEmpty) return text;
    if (!_otpContextRegex.hasMatch(text)) return text;
    return text.replaceAllMapped(_otpDigitRegex, (match) => '[REDACTED_OTP]');
  }

  /// Evaluates whether a notification passes ingestion criteria.
  /// Returns `false` if the notification should be dropped.
  bool shouldIngest(AppNotification notification) {
    // 1. System noise & ongoing filter
    if (blockSystemNoise) {
      if (notification.isOngoing) return false;
      final categoryLower = (notification.category ?? '').toLowerCase();
      if (_systemNoiseCategories.contains(categoryLower)) return false;
    }

    // 2. Package blocklist filter
    final pkgLower = notification.packageName.toLowerCase();
    if (blockedPackages.any((p) => p.toLowerCase() == pkgLower)) {
      return false;
    }

    // 3. Category exclusions filter
    final catLower = (notification.category ?? notification.classifiedCategory ?? '').toLowerCase();
    if (excludedCategories.any((c) => c.toLowerCase() == catLower)) {
      return false;
    }

    // Also check inferred category match (e.g. package hints or content)
    for (final excluded in excludedCategories) {
      final excLower = excluded.toLowerCase();
      if (excLower == 'finance' && _isFinancialContent(notification)) {
        return false;
      }
      if (excLower == 'social' && _isSocialContent(notification)) {
        return false;
      }
      if (excLower == 'health' && _isHealthContent(notification)) {
        return false;
      }
    }

    // 4. Financial protection mode
    if (financialProtectionEnabled) {
      if (catLower == 'finance' || _isFinancialContent(notification) || _containsOtp(notification)) {
        return false;
      }
    }

    return true;
  }

  /// Processes notification before ingestion.
  /// Returns `null` if the notification is dropped, or a sanitized instance if modified.
  AppNotification? processBeforeIngestion(AppNotification notification) {
    if (!shouldIngest(notification)) {
      return null;
    }

    if (otpMaskingEnabled) {
      final maskedTitle = maskOtpText(notification.title);
      final maskedContent = maskOtpText(notification.content);

      if (maskedTitle != notification.title || maskedContent != notification.content) {
        return notification.copyWith(
          title: maskedTitle,
          content: maskedContent,
        );
      }
    }

    return notification;
  }

  bool _containsOtp(AppNotification notification) {
    final text = '${notification.title} ${notification.content}';
    return _otpContextRegex.hasMatch(text) && _otpDigitRegex.hasMatch(text);
  }

  bool _isFinancialContent(AppNotification notification) {
    final text = '${notification.packageName} ${notification.title} ${notification.content}'.toLowerCase();
    return _financeKeywords.any((kw) => text.contains(kw));
  }

  bool _isSocialContent(AppNotification notification) {
    final text = '${notification.packageName} ${notification.title} ${notification.content}'.toLowerCase();
    return text.contains('instagram') ||
        text.contains('facebook') ||
        text.contains('twitter') ||
        text.contains('snapchat') ||
        text.contains('reddit') ||
        text.contains('linkedin') ||
        text.contains('tiktok');
  }

  bool _isHealthContent(AppNotification notification) {
    final text = '${notification.packageName} ${notification.title} ${notification.content}'.toLowerCase();
    return text.contains('health') ||
        text.contains('doctor') ||
        text.contains('hospital') ||
        text.contains('clinic') ||
        text.contains('prescription') ||
        text.contains('medicine') ||
        text.contains('pharmacy');
  }

  IngestionPolicy copyWith({
    Set<String>? blockedPackages,
    Set<String>? excludedCategories,
    bool? otpMaskingEnabled,
    bool? financialProtectionEnabled,
    bool? blockSystemNoise,
  }) {
    return IngestionPolicy(
      blockedPackages: blockedPackages ?? this.blockedPackages,
      excludedCategories: excludedCategories ?? this.excludedCategories,
      otpMaskingEnabled: otpMaskingEnabled ?? this.otpMaskingEnabled,
      financialProtectionEnabled: financialProtectionEnabled ?? this.financialProtectionEnabled,
      blockSystemNoise: blockSystemNoise ?? this.blockSystemNoise,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blockedPackages': blockedPackages.toList(),
      'excludedCategories': excludedCategories.toList(),
      'otpMaskingEnabled': otpMaskingEnabled,
      'financialProtectionEnabled': financialProtectionEnabled,
      'blockSystemNoise': blockSystemNoise,
    };
  }

  factory IngestionPolicy.fromMap(Map<String, dynamic> map) {
    return IngestionPolicy(
      blockedPackages: Set<String>.from(map['blockedPackages'] ?? []),
      excludedCategories: Set<String>.from(map['excludedCategories'] ?? []),
      otpMaskingEnabled: map['otpMaskingEnabled'] as bool? ?? true,
      financialProtectionEnabled: map['financialProtectionEnabled'] as bool? ?? false,
      blockSystemNoise: map['blockSystemNoise'] as bool? ?? true,
    );
  }
}
