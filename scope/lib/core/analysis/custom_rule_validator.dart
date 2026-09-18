import 'package:scope/core/analysis/rule_engine.dart';

/// Validates and sanitizes custom user-defined RLHF rules.
class CustomRuleValidator {
  static const int maxCustomRules = 50;
  static const int maxConditionItems = 10;
  static const int maxStringLength = 64;

  static const Set<String> reservedSystemIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
  };

  static const Set<String> validPriorities = {
    'high',
    'medium',
    'low',
  };

  static const Set<String> validCategories = {
    'promo',
    'social',
    'sys',
    'msg',
    'finance',
    'scholarship',
    'health',
    'email',
    'status',
    'other',
  };

  /// Sanitizes a single [NotificationRule].
  /// Returns a validated rule with [isCustom] set to true, or `null` if invalid.
  static NotificationRule? sanitize(NotificationRule rule) {
    // 1. Validate Rule ID
    final id = rule.id.trim();
    if (id.isEmpty) return null;
    if (reservedSystemIds.contains(id.toLowerCase())) return null;

    // Ensure custom prefix if missing
    final sanitizedId = id.startsWith('rlhf-') ? id : 'rlhf-$id';

    // 2. Validate & Sanitize Category
    final category = rule.category.trim().toLowerCase();
    if (category.isEmpty) return null;

    // 3. Validate & Clamp Priority
    String priority = rule.priority.trim().toLowerCase();
    if (priority == 'critical' || !validPriorities.contains(priority)) {
      priority = 'high';
    }

    // 4. Validate & Sanitize Conditions
    final packages = _sanitizeStringList(rule.conditions.packages);
    final keywords = _sanitizeStringList(rule.conditions.keywords);
    final titleKeywords = _sanitizeStringList(rule.conditions.titleKeywords);

    // Rule must have at least one non-empty condition criterion
    if (packages.isEmpty && keywords.isEmpty && titleKeywords.isEmpty) {
      return null;
    }

    return NotificationRule(
      id: sanitizedId,
      category: category,
      priority: priority,
      conditions: RuleCondition(
        packages: packages,
        keywords: keywords,
        titleKeywords: titleKeywords,
      ),
      isCustom: true,
    );
  }

  /// Sanitizes a list of custom rules, enforcing total rule count cap [maxCustomRules].
  static List<NotificationRule> sanitizeList(
    List<NotificationRule> rules, {
    int maxRules = maxCustomRules,
  }) {
    final sanitized = <NotificationRule>[];
    for (final rule in rules) {
      final valid = sanitize(rule);
      if (valid != null) {
        sanitized.add(valid);
        if (sanitized.length >= maxRules) break;
      }
    }
    return sanitized;
  }

  static List<String> _sanitizeStringList(List<String> list) {
    final result = <String>[];
    for (final item in list) {
      var trimmed = item.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.length > maxStringLength) {
          trimmed = trimmed.substring(0, maxStringLength);
        }
        result.add(trimmed);
        if (result.length >= maxConditionItems) break;
      }
    }
    return result;
  }
}
