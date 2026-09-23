import 'package:scope/core/analysis/rule_engine.dart';

/// Synchronous schema validator and sanitizer for custom user rules (RLHF).
class CustomRuleValidator {
  static const int maxCustomRules = 50;
  static const int maxStringLength = 64;
  static const int maxConditionItems = 10;

  /// System rule identifiers that must not be used or overwritten by custom rules.
  static const Set<String> reservedSystemRuleIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
    'family_urgent',
    'work_collaboration',
    'medical_reminder',
    'promo_deals',
    'social_engagement',
    'bank_debit',
  };

  /// Non-critical priority levels permitted for custom user rules.
  static const Set<String> validNonCriticalPriorities = {
    'high',
    'medium',
    'low',
  };

  /// Validates and sanitizes a custom [NotificationRule].
  /// Returns a valid, non-critical [NotificationRule], or `null` if the rule is invalid or malformed.
  static NotificationRule? validateAndSanitizeRule(NotificationRule rule) {
    var id = rule.id.trim();
    if (id.isEmpty) return null;

    final lowerId = id.toLowerCase();

    // Reject reserved system rule identifiers
    if (reservedSystemRuleIds.contains(lowerId)) {
      return null;
    }

    // Enforce required prefix (rlhf- or custom-)
    if (!id.startsWith('rlhf-') && !id.startsWith('custom-')) {
      id = 'rlhf-$id';
    }

    // Re-verify after prefixing
    if (reservedSystemRuleIds.contains(id.toLowerCase())) {
      return null;
    }

    // Downgrade critical priority or default invalid priority to medium
    String priority = rule.priority.trim().toLowerCase();
    if (priority == 'critical') {
      priority = 'high';
    } else if (!validNonCriticalPriorities.contains(priority)) {
      priority = 'medium';
    }

    // Validate category
    String category = rule.category.trim().toLowerCase();
    if (category.isEmpty) {
      category = 'personal';
    }

    // Validate and sanitize conditions
    final sanitizedConditions = sanitizeConditions(rule.conditions);
    if (sanitizedConditions == null) {
      return null; // Reject rules with no valid non-empty conditions
    }

    return NotificationRule(
      id: id,
      category: category,
      priority: priority,
      conditions: sanitizedConditions,
      isCustom: true,
    );
  }

  /// Sanitizes [RuleCondition] lists by removing empty/whitespace strings,
  /// enforcing string length limits, and capping list length.
  /// Returns `null` if no non-empty conditions remain.
  static RuleCondition? sanitizeConditions(RuleCondition conditions) {
    final cleanPackages = _cleanStringList(conditions.packages);
    final cleanKeywords = _cleanStringList(conditions.keywords);
    final cleanTitleKeywords = _cleanStringList(conditions.titleKeywords);

    // Rule must have at least one non-empty condition string
    if (cleanPackages.isEmpty && cleanKeywords.isEmpty && cleanTitleKeywords.isEmpty) {
      return null;
    }

    return RuleCondition(
      packages: cleanPackages,
      keywords: cleanKeywords,
      titleKeywords: cleanTitleKeywords,
    );
  }

  static List<String> _cleanStringList(List<String> rawList) {
    final clean = <String>[];
    for (final item in rawList) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) {
        final truncated = trimmed.length > maxStringLength
            ? trimmed.substring(0, maxStringLength)
            : trimmed;
        if (!clean.contains(truncated)) {
          clean.add(truncated);
        }
      }
      if (clean.length >= maxConditionItems) break;
    }
    return clean;
  }

  /// Sanitizes and validates a list of raw custom rule maps from JSON storage.
  static List<NotificationRule> validateCustomRuleList(List<dynamic> rawList) {
    final validRules = <NotificationRule>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      try {
        final map = Map<String, dynamic>.from(item);
        final rule = NotificationRule.fromMap(map, isCustom: true);
        final sanitized = validateAndSanitizeRule(rule);
        if (sanitized != null) {
          validRules.add(sanitized);
        }
      } catch (_) {
        // Skip malformed entries safely
        continue;
      }
      if (validRules.length >= maxCustomRules) break;
    }
    return validRules;
  }
}
