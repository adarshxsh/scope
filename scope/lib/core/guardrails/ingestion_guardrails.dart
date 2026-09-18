import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:scope/core/models/notification_model.dart';

/// Ingestion result status following guardrail evaluation.
enum IngestionResult {
  allowed,
  rejectedBlacklistedPackage,
  rejectedNotWhitelistedPackage,
  rejectedExcludedCategory,
  rejectedInvalidSchema,
}

/// Configuration policy for ingestion guardrails & exclusion controls.
class IngestionGuardrailPolicy {
  /// Packages that are explicitly blocked from ingestion.
  final Set<String> blacklistedPackages;

  /// Enable whitelist mode (if true, only packages in [whitelistedPackages] are accepted).
  final bool whitelistMode;

  /// Whitelisted packages (active when [whitelistMode] is true).
  final Set<String> whitelistedPackages;

  /// Categories that are excluded from persistent ingestion.
  final Set<String> excludedCategories;

  /// Maximum allowed title length (characters) before truncation.
  final int maxTitleLength;

  /// Maximum allowed content length (characters) before truncation.
  final int maxContentLength;

  /// Maximum allowed future timestamp drift (ms). Defaults to 24 hours.
  final int maxFutureTimestampWindowMs;

  /// Minimum valid timestamp threshold (ms). Defaults to 2020-01-01.
  final int minValidTimestampMs;

  const IngestionGuardrailPolicy({
    this.blacklistedPackages = const {
      'com.android.systemui.volume',
      'com.android.providers.downloads',
    },
    this.whitelistMode = false,
    this.whitelistedPackages = const {},
    this.excludedCategories = const {},
    this.maxTitleLength = 500,
    this.maxContentLength = 2000,
    this.maxFutureTimestampWindowMs = 86400000, // 24h
    this.minValidTimestampMs = 1577836800000, // 2020-01-01
  });

  IngestionGuardrailPolicy copyWith({
    Set<String>? blacklistedPackages,
    bool? whitelistMode,
    Set<String>? whitelistedPackages,
    Set<String>? excludedCategories,
    int? maxTitleLength,
    int? maxContentLength,
    int? maxFutureTimestampWindowMs,
    int? minValidTimestampMs,
  }) {
    return IngestionGuardrailPolicy(
      blacklistedPackages: blacklistedPackages ?? this.blacklistedPackages,
      whitelistMode: whitelistMode ?? this.whitelistMode,
      whitelistedPackages: whitelistedPackages ?? this.whitelistedPackages,
      excludedCategories: excludedCategories ?? this.excludedCategories,
      maxTitleLength: maxTitleLength ?? this.maxTitleLength,
      maxContentLength: maxContentLength ?? this.maxContentLength,
      maxFutureTimestampWindowMs:
          maxFutureTimestampWindowMs ?? this.maxFutureTimestampWindowMs,
      minValidTimestampMs: minValidTimestampMs ?? this.minValidTimestampMs,
    );
  }
}

/// Evaluation report from running ingestion guardrails.
class EvaluationReport {
  final IngestionResult result;
  final String? reason;
  final AppNotification? notification;

  const EvaluationReport({
    required this.result,
    this.reason,
    this.notification,
  });

  bool get isAllowed => result == IngestionResult.allowed;
}

/// Service providing input validation, package exclusion, category filtering,
/// and PII-redacted structured logging.
class IngestionGuardrailService {
  IngestionGuardrailPolicy _policy;

  IngestionGuardrailService({IngestionGuardrailPolicy? policy})
      : _policy = policy ?? const IngestionGuardrailPolicy();

  IngestionGuardrailPolicy get policy => _policy;

  void updatePolicy(IngestionGuardrailPolicy newPolicy) {
    _policy = newPolicy;
  }

  /// Evaluates and sanitizes an incoming notification against policy guardrails.
  EvaluationReport evaluateAndSanitize(AppNotification notification) {
    final pkg = notification.packageName.trim().toLowerCase();

    // 1. Schema / Package Name Validation
    if (pkg.isEmpty) {
      return const EvaluationReport(
        result: IngestionResult.rejectedInvalidSchema,
        reason: 'Empty or invalid package name',
      );
    }

    // Alphanumeric + dot + underscore package format check
    final pkgRegExp = RegExp(r'^[a-zA-Z0-9_.]+$');
    if (!pkgRegExp.hasMatch(pkg)) {
      return EvaluationReport(
        result: IngestionResult.rejectedInvalidSchema,
        reason: 'Malformed package name: $pkg',
      );
    }

    // 2. Package Blacklist Check
    if (_policy.blacklistedPackages.map((p) => p.toLowerCase()).contains(pkg)) {
      return EvaluationReport(
        result: IngestionResult.rejectedBlacklistedPackage,
        reason: 'Package $pkg is blacklisted',
      );
    }

    // 3. Package Whitelist Check
    if (_policy.whitelistMode) {
      final allowed = _policy.whitelistedPackages
          .map((p) => p.toLowerCase())
          .contains(pkg);
      if (!allowed) {
        return EvaluationReport(
          result: IngestionResult.rejectedNotWhitelistedPackage,
          reason: 'Package $pkg is not whitelisted',
        );
      }
    }

    // 4. Category Exclusion Check
    final rawCat = (notification.category ?? '').trim().toLowerCase();
    final classifiedCat = (notification.classifiedCategory ?? '').trim().toLowerCase();
    
    for (final excluded in _policy.excludedCategories) {
      final exLower = excluded.trim().toLowerCase();
      if (rawCat == exLower || classifiedCat == exLower) {
        return EvaluationReport(
          result: IngestionResult.rejectedExcludedCategory,
          reason: 'Category $excluded is excluded',
        );
      }
    }

    // 5. Schema Normalization & Sanitization
    final now = DateTime.now().millisecondsSinceEpoch;
    int ts = notification.timestamp;
    if (ts < _policy.minValidTimestampMs ||
        ts > now + _policy.maxFutureTimestampWindowMs) {
      ts = now; // Normalize invalid timestamp to current epoch
    }

    String title = notification.title;
    if (title.length > _policy.maxTitleLength) {
      title = title.substring(0, _policy.maxTitleLength);
    }

    String content = notification.content;
    if (content.length > _policy.maxContentLength) {
      content = content.substring(0, _policy.maxContentLength);
    }

    final sanitized = notification.copyWith(
      title: title,
      content: content,
      timestamp: ts,
    );

    return EvaluationReport(
      result: IngestionResult.allowed,
      notification: sanitized,
    );
  }

  /// Formats structured diagnostic logs without cleartext PII (titles or bodies).
  String formatDiagnosticLog(AppNotification notification, {String? tag}) {
    final pkg = notification.packageName;
    final titleLen = notification.title.length;
    final contentLen = notification.content.length;
    final titleHash = sha256.convert(utf8.encode(notification.title)).toString().substring(0, 8);
    final contentHash = sha256.convert(utf8.encode(notification.content)).toString().substring(0, 8);

    final prefix = tag != null ? '[$tag] ' : '';
    return '${prefix}IngestionLog(id: ${notification.id}, package: $pkg, titleLen: $titleLen [hash:$titleHash], contentLen: $contentLen [hash:$contentHash], category: ${notification.category}, isOngoing: ${notification.isOngoing})';
  }
}
