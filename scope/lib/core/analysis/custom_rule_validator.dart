import 'package:scope/core/analysis/rule_engine.dart';

/// Validates user-defined custom RLHF rules against structural schema constraints,
/// reserved system IDs, priority ceilings, and execution bounds.
class CustomRuleValidator {
  /// System IDs reserved for base security and core classifier rules.
  static const Set<String> reservedIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
  };

  /// Maximum allowed custom rules in total.
  static const int maxCustomRules = 50;

  /// Maximum allowed packages in a single condition.
  static const int maxPackages = 10;

  /// Maximum allowed content keywords in a single condition.
  static const int maxKeywords = 10;

  /// Maximum allowed title keywords in a single condition.
  static const int maxTitleKeywords = 10;

  /// Maximum allowed character length for any package or keyword string.
  static const int maxKeywordLength = 64;

  /// Validates and sanitizes a custom [NotificationRule].
  ///
  /// Returns a sanitized copy of the rule if valid (with priority clamped to non-critical levels),
  /// or `null` if the rule violates schema bounds or uses reserved identifiers.
  static NotificationRule? validate(NotificationRule rule) {
    final trimmedId = rule.id.trim();

    // 1. Reserved System ID and empty ID sanitization
    if (trimmedId.isEmpty || reservedIds.contains(trimmedId.toLowerCase())) {
      return null;
    }

    final cond = rule.conditions;

    // 2. Capacity bounds per condition
    if (cond.packages.length > maxPackages ||
        cond.titleKeywords.length > maxTitleKeywords ||
        cond.keywords.length > maxKeywords) {
      return null;
    }

    // 3. Keyword/package string length limits
    for (final p in cond.packages) {
      if (p.length > maxKeywordLength) return null;
    }
    for (final k in cond.titleKeywords) {
      if (k.length > maxKeywordLength) return null;
    }
    for (final k in cond.keywords) {
      if (k.length > maxKeywordLength) return null;
    }

    // 4. Mandatory non-empty condition requirement
    final validPackages = cond.packages.where((p) => p.trim().isNotEmpty).toList();
    final validTitleKw = cond.titleKeywords.where((k) => k.trim().isNotEmpty).toList();
    final validContentKw = cond.keywords.where((k) => k.trim().isNotEmpty).toList();

    if (validPackages.isEmpty && validTitleKw.isEmpty && validContentKw.isEmpty) {
      return null;
    }

    // 5. Priority Ceiling: Clamp 'critical' to 'high'
    String priority = rule.priority.toLowerCase().trim();
    if (priority == 'critical') {
      priority = 'high';
    } else if (priority.isEmpty) {
      priority = 'high';
    }

    return NotificationRule(
      id: trimmedId,
      category: rule.category.trim().isEmpty ? 'custom' : rule.category,
      priority: priority,
      conditions: RuleCondition(
        packages: validPackages,
        titleKeywords: validTitleKw,
        keywords: validContentKw,
      ),
    );
  }
}
