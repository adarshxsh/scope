import 'package:flutter/foundation.dart';
import 'package:scope/core/analysis/rule_engine.dart';

/// Schema validator and sanitizer for user-defined custom RLHF rules.
class CustomRuleValidator {
  /// System rule identifiers that custom rules are strictly forbidden from impersonating.
  static const Set<String> reservedSystemIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
    'bank_debit',
  };

  /// Allowed priority levels for custom rules.
  static const Set<String> validCustomPriorities = {
    'high',
    'medium',
    'low',
  };

  /// Validates and sanitizes a [NotificationRule].
  ///
  /// Enforces structural and security constraints:
  /// 1. ID must be non-empty and must not impersonate system rule identifiers.
  /// 2. Conditions must contain at least one non-empty package, title keyword, or content keyword.
  /// 3. Priority `'critical'` is automatically downgraded to `'high'`.
  /// 4. Invalid or unknown priority strings result in rejection (`null`).
  ///
  /// Returns a sanitized [NotificationRule] if valid, or `null` if the rule is invalid and must be rejected.
  static NotificationRule? validateAndSanitize(
    NotificationRule rule, {
    Set<String>? systemRuleIds,
  }) {
    final cleanId = rule.id.trim();
    if (cleanId.isEmpty) {
      debugPrint('CustomRuleValidator: Rejected rule with empty ID.');
      return null;
    }

    // Check system rule identifier impersonation
    final lowerId = cleanId.toLowerCase();
    if (reservedSystemIds.contains(lowerId)) {
      debugPrint('CustomRuleValidator: Rejected rule impersonating reserved system ID "$cleanId".');
      return null;
    }

    if (systemRuleIds != null && systemRuleIds.contains(cleanId)) {
      debugPrint('CustomRuleValidator: Rejected rule impersonating active system rule ID "$cleanId".');
      return null;
    }

    // Check condition constraints (must contain at least one non-empty condition)
    final hasPackage = rule.conditions.packages.any((p) => p.trim().isNotEmpty);
    final hasTitleKeyword = rule.conditions.titleKeywords.any((k) => k.trim().isNotEmpty);
    final hasKeyword = rule.conditions.keywords.any((k) => k.trim().isNotEmpty);

    if (!hasPackage && !hasTitleKeyword && !hasKeyword) {
      debugPrint('CustomRuleValidator: Rejected rule "$cleanId" with no non-empty matching conditions.');
      return null;
    }

    // Sanitize conditions by filtering out empty strings
    final cleanPackages = rule.conditions.packages
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final cleanTitleKeywords = rule.conditions.titleKeywords
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    final cleanKeywords = rule.conditions.keywords
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    // Check priority constraints
    final rawPriority = rule.priority.trim().toLowerCase();
    String sanitizedPriority;

    if (rawPriority == 'critical') {
      debugPrint('CustomRuleValidator: Downgrading critical priority to high for custom rule "$cleanId".');
      sanitizedPriority = 'high';
    } else if (validCustomPriorities.contains(rawPriority)) {
      sanitizedPriority = rawPriority;
    } else {
      debugPrint('CustomRuleValidator: Rejected rule "$cleanId" with invalid priority "$rawPriority".');
      return null;
    }

    return NotificationRule(
      id: cleanId,
      category: rule.category.trim().isEmpty ? 'general' : rule.category.trim(),
      priority: sanitizedPriority,
      conditions: RuleCondition(
        packages: cleanPackages,
        titleKeywords: cleanTitleKeywords,
        keywords: cleanKeywords,
      ),
    );
  }

  /// Parses a raw map structure and validates/sanitizes it into a [NotificationRule].
  /// Returns `null` if the map is malformed or violates security constraints.
  static NotificationRule? validateAndSanitizeMap(
    Map<String, dynamic> map, {
    Set<String>? systemRuleIds,
  }) {
    try {
      final rule = NotificationRule.fromMap(map);
      return validateAndSanitize(rule, systemRuleIds: systemRuleIds);
    } catch (e) {
      debugPrint('CustomRuleValidator: Failed to parse custom rule map: $e');
      return null;
    }
  }
}
