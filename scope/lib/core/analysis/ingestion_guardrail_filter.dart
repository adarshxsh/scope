import 'package:flutter/foundation.dart';
import 'package:scope/core/analysis/metadata_analyzer.dart';
import 'package:scope/core/models/notification_model.dart';

/// Sensitive categories that users can exclude from notification ingestion.
enum SensitiveCategory {
  bankingFinance,
  otpSecurity,
  healthMedical,
  personalMessaging,
}

extension SensitiveCategoryExtension on SensitiveCategory {
  String get nameString {
    switch (this) {
      case SensitiveCategory.bankingFinance:
        return 'banking_finance';
      case SensitiveCategory.otpSecurity:
        return 'otp_security';
      case SensitiveCategory.healthMedical:
        return 'health_medical';
      case SensitiveCategory.personalMessaging:
        return 'personal_messaging';
    }
  }

  String get label {
    switch (this) {
      case SensitiveCategory.bankingFinance:
        return 'Banking & Finance';
      case SensitiveCategory.otpSecurity:
        return 'OTP & Security';
      case SensitiveCategory.healthMedical:
        return 'Health & Medical';
      case SensitiveCategory.personalMessaging:
        return 'Personal Messaging';
    }
  }

  String get description {
    switch (this) {
      case SensitiveCategory.bankingFinance:
        return 'Bank alerts, transaction receipts, UPI requests, and financial updates';
      case SensitiveCategory.otpSecurity:
        return 'Verification codes, OTPs, passcodes, and security alerts';
      case SensitiveCategory.healthMedical:
        return 'Health records, prescription updates, and doctor appointments';
      case SensitiveCategory.personalMessaging:
        return 'Direct messages, personal chat notifications, and private conversations';
    }
  }

  static SensitiveCategory? fromString(String val) {
    final lower = val.toLowerCase().trim();
    if (lower == 'banking_finance' || lower == 'finance' || lower == 'banking' || lower == 'upi') {
      return SensitiveCategory.bankingFinance;
    }
    if (lower == 'otp_security' || lower == 'otp' || lower == 'security' || lower == 'auth') {
      return SensitiveCategory.otpSecurity;
    }
    if (lower == 'health_medical' || lower == 'health' || lower == 'medical') {
      return SensitiveCategory.healthMedical;
    }
    if (lower == 'personal_messaging' || lower == 'msg' || lower == 'messaging' || lower == 'chat') {
      return SensitiveCategory.personalMessaging;
    }
    return null;
  }
}

/// Configuration settings for notification ingestion guardrails.
class IngestionGuardrailConfig {
  final Set<String> blacklistedPackages;
  final Set<String> whitelistedPackages;
  final bool isWhitelistModeEnabled;
  final Set<SensitiveCategory> excludedCategories;
  final int maxTitleLength;
  final int maxContentLength;
  final bool allowFutureTimestamps;

  const IngestionGuardrailConfig({
    this.blacklistedPackages = const {},
    this.whitelistedPackages = const {},
    this.isWhitelistModeEnabled = false,
    this.excludedCategories = const {},
    this.maxTitleLength = 1000,
    this.maxContentLength = 5000,
    this.allowFutureTimestamps = false,
  });

  IngestionGuardrailConfig copyWith({
    Set<String>? blacklistedPackages,
    Set<String>? whitelistedPackages,
    bool? isWhitelistModeEnabled,
    Set<SensitiveCategory>? excludedCategories,
    int? maxTitleLength,
    int? maxContentLength,
    bool? allowFutureTimestamps,
  }) {
    return IngestionGuardrailConfig(
      blacklistedPackages: blacklistedPackages ?? this.blacklistedPackages,
      whitelistedPackages: whitelistedPackages ?? this.whitelistedPackages,
      isWhitelistModeEnabled: isWhitelistModeEnabled ?? this.isWhitelistModeEnabled,
      excludedCategories: excludedCategories ?? this.excludedCategories,
      maxTitleLength: maxTitleLength ?? this.maxTitleLength,
      maxContentLength: maxContentLength ?? this.maxContentLength,
      allowFutureTimestamps: allowFutureTimestamps ?? this.allowFutureTimestamps,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blacklistedPackages': blacklistedPackages.toList(),
      'whitelistedPackages': whitelistedPackages.toList(),
      'isWhitelistModeEnabled': isWhitelistModeEnabled,
      'excludedCategories': excludedCategories.map((c) => c.nameString).toList(),
      'maxTitleLength': maxTitleLength,
      'maxContentLength': maxContentLength,
      'allowFutureTimestamps': allowFutureTimestamps,
    };
  }

  factory IngestionGuardrailConfig.fromMap(Map<String, dynamic> map) {
    final blacklist = (map['blacklistedPackages'] as List?)
            ?.map((e) => e.toString().toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        {};
    final whitelist = (map['whitelistedPackages'] as List?)
            ?.map((e) => e.toString().toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        {};
    final categoriesList = (map['excludedCategories'] as List?) ?? [];
    final categories = <SensitiveCategory>{};
    for (final catStr in categoriesList) {
      final parsed = SensitiveCategoryExtension.fromString(catStr.toString());
      if (parsed != null) categories.add(parsed);
    }

    return IngestionGuardrailConfig(
      blacklistedPackages: blacklist,
      whitelistedPackages: whitelist,
      isWhitelistModeEnabled: map['isWhitelistModeEnabled'] as bool? ?? false,
      excludedCategories: categories,
      maxTitleLength: map['maxTitleLength'] as int? ?? 1000,
      maxContentLength: map['maxContentLength'] as int? ?? 5000,
      allowFutureTimestamps: map['allowFutureTimestamps'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IngestionGuardrailConfig &&
        isWhitelistModeEnabled == other.isWhitelistModeEnabled &&
        maxTitleLength == other.maxTitleLength &&
        maxContentLength == other.maxContentLength &&
        allowFutureTimestamps == other.allowFutureTimestamps &&
        setEquals(blacklistedPackages, other.blacklistedPackages) &&
        setEquals(whitelistedPackages, other.whitelistedPackages) &&
        setEquals(excludedCategories, other.excludedCategories);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(blacklistedPackages),
        Object.hashAll(whitelistedPackages),
        isWhitelistModeEnabled,
        Object.hashAll(excludedCategories),
        maxTitleLength,
        maxContentLength,
        allowFutureTimestamps,
      );
}

/// Telemetry metrics tracking for notification ingestion.
class IngestionTelemetry {
  int totalEvaluated = 0;
  int totalIngested = 0;
  int totalExcludedBlacklist = 0;
  int totalExcludedWhitelist = 0;
  int totalExcludedSensitiveCategory = 0;
  int totalRejectedValidation = 0;
  int totalErrors = 0;

  IngestionTelemetry();

  void reset() {
    totalEvaluated = 0;
    totalIngested = 0;
    totalExcludedBlacklist = 0;
    totalExcludedWhitelist = 0;
    totalExcludedSensitiveCategory = 0;
    totalRejectedValidation = 0;
    totalErrors = 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'totalEvaluated': totalEvaluated,
      'totalIngested': totalIngested,
      'totalExcludedBlacklist': totalExcludedBlacklist,
      'totalExcludedWhitelist': totalExcludedWhitelist,
      'totalExcludedSensitiveCategory': totalExcludedSensitiveCategory,
      'totalRejectedValidation': totalRejectedValidation,
      'totalErrors': totalErrors,
    };
  }

  factory IngestionTelemetry.fromMap(Map<String, dynamic> map) {
    final t = IngestionTelemetry();
    t.totalEvaluated = map['totalEvaluated'] as int? ?? 0;
    t.totalIngested = map['totalIngested'] as int? ?? 0;
    t.totalExcludedBlacklist = map['totalExcludedBlacklist'] as int? ?? 0;
    t.totalExcludedWhitelist = map['totalExcludedWhitelist'] as int? ?? 0;
    t.totalExcludedSensitiveCategory = map['totalExcludedSensitiveCategory'] as int? ?? 0;
    t.totalRejectedValidation = map['totalRejectedValidation'] as int? ?? 0;
    t.totalErrors = map['totalErrors'] as int? ?? 0;
    return t;
  }

  String summary() {
    return 'Evaluated: $totalEvaluated | Ingested: $totalIngested | '
        'Blacklisted: $totalExcludedBlacklist | Whitelisted Blocked: $totalExcludedWhitelist | '
        'Sensitive Excluded: $totalExcludedSensitiveCategory | Invalid: $totalRejectedValidation | Errors: $totalErrors';
  }
}

/// Result of evaluating a notification against ingestion guardrails.
class IngestionEvaluationResult {
  final bool isAllowed;
  final String reason;
  final SensitiveCategory? sensitiveCategory;
  final AppNotification? sanitizedNotification;

  const IngestionEvaluationResult.allow(this.sanitizedNotification)
      : isAllowed = true,
        reason = 'allowed',
        sensitiveCategory = null;

  const IngestionEvaluationResult.exclude({
    required this.reason,
    this.sensitiveCategory,
  })  : isAllowed = false,
        sanitizedNotification = null;
}

/// Evaluates notifications prior to ingestion into local SQLite storage.
class IngestionGuardrailFilter {
  IngestionGuardrailConfig config;
  final IngestionTelemetry telemetry;

  IngestionGuardrailFilter({
    IngestionGuardrailConfig? config,
    IngestionTelemetry? telemetry,
  })  : config = config ?? const IngestionGuardrailConfig(),
        telemetry = telemetry ?? IngestionTelemetry();

  /// Evaluates an [AppNotification] against pre-ingestion validation rules,
  /// package whitelist/blacklist controls, and sensitive app category exclusions.
  IngestionEvaluationResult evaluate(AppNotification notification) {
    telemetry.totalEvaluated++;

    try {
      final pkg = notification.packageName.toLowerCase().trim();

      // 1. Validation Guardrails
      if (pkg.isEmpty) {
        telemetry.totalRejectedValidation++;
        _logSanitized('REJECTED', pkg, 'Empty or missing package name');
        return const IngestionEvaluationResult.exclude(
          reason: 'invalid_package_name',
        );
      }

      if (notification.timestamp <= 0) {
        telemetry.totalRejectedValidation++;
        _logSanitized('REJECTED', pkg, 'Invalid non-positive timestamp');
        return const IngestionEvaluationResult.exclude(
          reason: 'invalid_timestamp',
        );
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (!config.allowFutureTimestamps && notification.timestamp > (nowMs + 300000)) {
        telemetry.totalRejectedValidation++;
        _logSanitized('REJECTED', pkg, 'Timestamp is in the future (>5 mins ahead)');
        return const IngestionEvaluationResult.exclude(
          reason: 'future_timestamp_exceeded',
        );
      }

      // Payload length sanitization / validation
      String sanitizedTitle = notification.title;
      String sanitizedContent = notification.content;

      if (sanitizedTitle.length > config.maxTitleLength) {
        sanitizedTitle = sanitizedTitle.substring(0, config.maxTitleLength);
      }
      if (sanitizedContent.length > config.maxContentLength) {
        sanitizedContent = sanitizedContent.substring(0, config.maxContentLength);
      }

      // 2. Package Blacklist Guardrails
      if (config.blacklistedPackages.contains(pkg)) {
        telemetry.totalExcludedBlacklist++;
        _logSanitized('EXCLUDED', pkg, 'Package is blacklisted');
        return const IngestionEvaluationResult.exclude(
          reason: 'package_blacklisted',
        );
      }

      // 3. Package Whitelist Guardrails (when whitelist mode is enabled)
      if (config.isWhitelistModeEnabled && !config.whitelistedPackages.contains(pkg)) {
        telemetry.totalExcludedWhitelist++;
        _logSanitized('EXCLUDED', pkg, 'Package not in whitelist (whitelist mode active)');
        return const IngestionEvaluationResult.exclude(
          reason: 'package_not_whitelisted',
        );
      }

      // 4. Sensitive Category Detection & Exclusion Controls
      final detectedCategory = detectSensitiveCategory(notification);
      if (detectedCategory != null && config.excludedCategories.contains(detectedCategory)) {
        telemetry.totalExcludedSensitiveCategory++;
        _logSanitized('EXCLUDED', pkg, 'Sensitive category excluded: ${detectedCategory.label}');
        return IngestionEvaluationResult.exclude(
          reason: 'sensitive_category_excluded_${detectedCategory.nameString}',
          sensitiveCategory: detectedCategory,
        );
      }

      // 5. Permitted for Ingestion
      telemetry.totalIngested++;
      _logSanitized('ALLOWED', pkg, 'Notification passed ingestion guardrails');

      final sanitizedNotif = (sanitizedTitle != notification.title || sanitizedContent != notification.content)
          ? notification.copyWith(title: sanitizedTitle, content: sanitizedContent)
          : notification;

      return IngestionEvaluationResult.allow(sanitizedNotif);
    } catch (e) {
      telemetry.totalErrors++;
      _logSanitized('ERROR', notification.packageName, 'Guardrail evaluation error: ${e.runtimeType}');
      return const IngestionEvaluationResult.exclude(reason: 'evaluation_error');
    }
  }

  /// Detects whether a notification belongs to a sensitive app category.
  SensitiveCategory? detectSensitiveCategory(AppNotification notification) {
    final pkg = notification.packageName.toLowerCase().trim();
    final rawCategory = (notification.category ?? '').toLowerCase().trim();
    final classifiedCategory = (notification.classifiedCategory ?? '').toLowerCase().trim();
    final titleLower = notification.title.toLowerCase();
    final contentLower = notification.content.toLowerCase();
    final combined = '$titleLower $contentLower';

    // A. Banking & Finance
    final isFinancePackage = MetadataAnalyzer.packageCategoryMap[pkg] == 'finance' ||
        pkg.contains('bank') ||
        pkg.contains('paytm') ||
        pkg.contains('phonepe') ||
        pkg.contains('groww') ||
        pkg.contains('zerodha') ||
        pkg.contains('cred') ||
        pkg.contains('gpay');

    final isFinanceCategory = rawCategory == 'finance' || rawCategory == 'upi' || classifiedCategory == 'finance' || classifiedCategory == 'upi';

    final hasFinanceKeywords = combined.contains('debited') ||
        combined.contains('credited') ||
        combined.contains('account balance') ||
        combined.contains('bank transfer') ||
        combined.contains('upi collect') ||
        combined.contains('transaction alert') ||
        combined.contains('payment successful') ||
        combined.contains('withdrawal') ||
        combined.contains('deposit');

    if (isFinancePackage || isFinanceCategory || hasFinanceKeywords) {
      return SensitiveCategory.bankingFinance;
    }

    // B. OTP & Security
    final isSecurityCategory = rawCategory == 'otp' || rawCategory == 'security' || classifiedCategory == 'otp' || classifiedCategory == 'security';

    final isOtpPattern = RegExp(r'\b(otp|verification code|verify code|security code|login code|2fa|one time password)\b', caseSensitive: false)
            .hasMatch(combined) ||
        (RegExp(r'\b\d{4,8}\b').hasMatch(combined) &&
            (combined.contains('code') || combined.contains('verify') || combined.contains('password') || combined.contains('sign-in')));

    if (isSecurityCategory || isOtpPattern) {
      return SensitiveCategory.otpSecurity;
    }

    // C. Health & Medical
    final isHealthPackage = MetadataAnalyzer.packageCategoryMap[pkg] == 'health' ||
        pkg.contains('health') ||
        pkg.contains('patient') ||
        pkg.contains('hospital') ||
        pkg.contains('doctor') ||
        pkg.contains('pharmacy') ||
        pkg.contains('apollo') ||
        pkg.contains('practo');

    final isHealthCategory = rawCategory == 'health' || rawCategory == 'medical' || classifiedCategory == 'health';

    final hasHealthKeywords = combined.contains('prescription') ||
        combined.contains('lab test') ||
        combined.contains('doctor appointment') ||
        combined.contains('medical report') ||
        combined.contains('patient id');

    if (isHealthPackage || isHealthCategory || hasHealthKeywords) {
      return SensitiveCategory.healthMedical;
    }

    // D. Personal Messaging
    final isMessagingPackage = MetadataAnalyzer.packageCategoryMap[pkg] == 'msg' ||
        pkg == 'com.whatsapp' ||
        pkg == 'com.slack' ||
        pkg == 'org.telegram.messenger' ||
        pkg == 'com.facebook.orca' ||
        pkg == 'com.google.android.talk' ||
        pkg == 'com.discord';

    final isMessagingCategory = rawCategory == 'msg' || rawCategory == 'conversation' || rawCategory == 'message';

    if (isMessagingPackage || isMessagingCategory) {
      return SensitiveCategory.personalMessaging;
    }

    return null;
  }

  /// Safe sanitized logging function that strictly refrains from logging
  /// any cleartext notification title, content, or personal data.
  void _logSanitized(String status, String packageName, String message) {
    if (kDebugMode) {
      // Print ONLY metadata & sanitized status. No user content or OTPs.
      // ignore: avoid_print
      print('[IngestionGuardrail] [$status] pkg: "$packageName" | $message');
    }
  }
}
