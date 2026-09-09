import 'package:scope/core/models/notification_model.dart';

/// Pre-persistence privacy engine for evaluating incoming notifications
/// against user-defined package blacklists, sensitive category exclusions,
/// and field-level sanitization rules.
class PrivacyEngine {
  final Set<String> _blacklistedPackages = {};
  final Set<String> _excludedCategories = {};
  bool _excludeOtpAndHealth = false;
  bool _excludeFinance = false;
  bool _fieldSanitizationEnabled = false;

  Set<String> get blacklistedPackages => Set.unmodifiable(_blacklistedPackages);
  Set<String> get excludedCategories => Set.unmodifiable(_excludedCategories);
  bool get excludeOtpAndHealth => _excludeOtpAndHealth;
  bool get excludeFinance => _excludeFinance;
  bool get fieldSanitizationEnabled => _fieldSanitizationEnabled;

  /// Returns effective category rules list for native channel sync.
  List<String> get effectiveCategoryRules {
    final rules = Set<String>.from(_excludedCategories);
    if (_excludeOtpAndHealth) {
      rules.addAll(['otp', 'health', 'medical', 'security', 'authentication']);
    }
    if (_excludeFinance) {
      rules.addAll(['finance', 'banking', 'upi']);
    }
    return rules.toList();
  }

  void setBlacklistedPackages(Iterable<String> packages) {
    _blacklistedPackages.clear();
    _blacklistedPackages.addAll(packages);
  }

  void addBlacklistedPackage(String packageName) {
    _blacklistedPackages.add(packageName);
  }

  void removeBlacklistedPackage(String packageName) {
    _blacklistedPackages.remove(packageName);
  }

  bool isPackageBlacklisted(String packageName) {
    return _blacklistedPackages.contains(packageName);
  }

  void setExcludedCategories(Iterable<String> categories) {
    _excludedCategories.clear();
    _excludedCategories.addAll(categories.map((c) => c.toLowerCase()));
  }

  void setSensitiveCategoryRules({
    bool? excludeOtpAndHealth,
    bool? excludeFinance,
  }) {
    if (excludeOtpAndHealth != null) _excludeOtpAndHealth = excludeOtpAndHealth;
    if (excludeFinance != null) _excludeFinance = excludeFinance;
  }

  void setFieldSanitization(bool enabled) {
    _fieldSanitizationEnabled = enabled;
  }

  /// Evaluates whether an incoming notification should be dropped prior to persistence.
  bool shouldDrop(AppNotification notification) {
    // 1. Package blacklist check
    if (_blacklistedPackages.contains(notification.packageName)) {
      return true;
    }

    // 2. Explicit excluded category string check
    final cat = (notification.category ?? notification.classifiedCategory ?? '').toLowerCase();
    if (cat.isNotEmpty) {
      if (_excludedCategories.contains(cat) ||
          _excludedCategories.any((e) => cat == e || cat.contains(e))) {
        return true;
      }
    }

    // 3. OTP & Health auto-exclusion check
    if (_excludeOtpAndHealth) {
      if (_isOtpOrHealthNotification(notification)) {
        return true;
      }
    }

    // 4. Finance auto-exclusion check
    if (_excludeFinance) {
      if (_isFinanceNotification(notification)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if notification matches OTP / 2FA or Health metadata.
  bool _isOtpOrHealthNotification(AppNotification n) {
    final cat = (n.category ?? n.classifiedCategory ?? '').toLowerCase();
    final title = n.title.toLowerCase();
    final body = n.content.toLowerCase();

    if (cat == 'otp' || cat == 'health' || cat == 'medical' || cat == 'security' || cat == 'authentication') {
      return true;
    }

    final features = n.extractedFeatures;
    if (features != null && features['containsOtp'] == true) {
      return true;
    }

    const otpKeywords = [
      'otp',
      'verification code',
      'verify code',
      'one-time password',
      'security code',
      'reset code',
      'sign-in code',
      'auth code',
      '2fa'
    ];
    for (final kw in otpKeywords) {
      if (title.contains(kw) || body.contains(kw)) {
        return true;
      }
    }

    const healthKeywords = [
      'medical',
      'doctor',
      'hospital',
      'health',
      'prescription',
      'patient',
      'clinic',
      'pharmacy',
      'lab result'
    ];
    for (final kw in healthKeywords) {
      if (title.contains(kw) || body.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if notification matches Finance / Banking metadata.
  bool _isFinanceNotification(AppNotification n) {
    final cat = (n.category ?? n.classifiedCategory ?? '').toLowerCase();
    if (cat == 'finance' || cat == 'banking' || cat == 'upi') {
      return true;
    }

    final features = n.extractedFeatures;
    if (features != null && features['amount'] != null) {
      return true;
    }

    final title = n.title.toLowerCase();
    final body = n.content.toLowerCase();
    const financeKeywords = [
      'bank',
      'account',
      'transfer',
      'payment',
      'balance',
      'credited',
      'debited',
      'upi'
    ];
    for (final kw in financeKeywords) {
      if (title.contains(kw) || body.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  /// Applies optional field-level sanitization (masking OTP numbers and monetary amounts).
  AppNotification sanitize(AppNotification notification) {
    if (!_fieldSanitizationEnabled) return notification;

    String title = notification.title;
    String content = notification.content;

    // Mask monetary amounts (e.g., ₹249, ₹15,499, $100.00, Rs. 500)
    final moneyRegex = RegExp(
      r'(?:₹|Rs\.?|\$|USD|EUR)\s?\d+(?:,\d+)*(?:\.\d+)?\b',
      caseSensitive: false,
    );
    title = title.replaceAllMapped(moneyRegex, (match) => '[AMOUNT REDACTED]');
    content = content.replaceAllMapped(moneyRegex, (match) => '[AMOUNT REDACTED]');

    // Mask numerical OTPs (4-8 digit numbers in OTP/Verification contexts)
    final otpRegex = RegExp(r'\b\d{4,8}\b');
    if (_isOtpOrHealthNotification(notification) ||
        content.toLowerCase().contains('otp') ||
        content.toLowerCase().contains('code') ||
        content.toLowerCase().contains('verify')) {
      title = title.replaceAllMapped(otpRegex, (match) => '[REDACTED]');
      content = content.replaceAllMapped(otpRegex, (match) => '[REDACTED]');
    }

    if (title == notification.title && content == notification.content) {
      return notification;
    }

    return notification.copyWith(
      title: title,
      content: content,
    );
  }
}
