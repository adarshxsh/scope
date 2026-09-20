import 'package:scope/core/analysis/rule_engine.dart';

/// Validator and sanitizer for user-defined custom RLHF rules.
class CustomRuleValidator {
  static const int maxCustomRules = 50;
  static const int maxKeywords = 10;
  static const int maxPackages = 10;
  static const int minKeywordLength = 3;
  static const int maxStringLength = 64;

  static const Set<String> reservedSystemRuleIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
  };

  /// Validates raw Map structure for a custom rule before deserialization.
  static bool isValidRuleMap(Map<String, dynamic> map) {
    // 1. Check ID
    final id = map['id'];
    if (id is! String || id.trim().isEmpty || id.length > maxStringLength) {
      return false;
    }
    if (reservedSystemRuleIds.contains(id.trim())) {
      return false;
    }

    // 2. Check Category
    final category = map['category'];
    if (category is! String || category.trim().isEmpty || category.length > maxStringLength) {
      return false;
    }

    // 3. Check Priority
    final priority = map['priority'];
    if (priority is! String || priority.trim().isEmpty) {
      return false;
    }

    // 4. Check Conditions
    final rawConditions = map['conditions'];
    if (rawConditions is! Map) {
      return false;
    }
    final conditions = Map<String, dynamic>.from(rawConditions);

    int validKeywordsCount = 0;
    int validTitleKeywordsCount = 0;
    int validPackagesCount = 0;

    if (conditions.containsKey('keywords')) {
      final keywords = conditions['keywords'];
      if (keywords is! Iterable) return false;
      if (keywords.length > maxKeywords) return false;
      for (final kw in keywords) {
        if (kw is! String) return false;
        if (kw.length > maxStringLength) return false;
        if (kw.trim().length >= minKeywordLength) {
          validKeywordsCount++;
        }
      }
    }

    if (conditions.containsKey('title_keywords')) {
      final titleKeywords = conditions['title_keywords'];
      if (titleKeywords is! Iterable) return false;
      if (titleKeywords.length > maxKeywords) return false;
      for (final kw in titleKeywords) {
        if (kw is! String) return false;
        if (kw.length > maxStringLength) return false;
        if (kw.trim().length >= minKeywordLength) {
          validTitleKeywordsCount++;
        }
      }
    }

    if (conditions.containsKey('packages')) {
      final packages = conditions['packages'];
      if (packages is! Iterable) return false;
      if (packages.length > maxPackages) return false;
      for (final pkg in packages) {
        if (pkg is! String || pkg.trim().isEmpty || pkg.length > maxStringLength) {
          return false;
        }
        validPackagesCount++;
      }
    }

    // Rule must have at least one valid condition after bounds filtering
    return (validKeywordsCount + validTitleKeywordsCount + validPackagesCount) > 0;
  }

  /// Clamps priority and sanitizes condition bounds for a [NotificationRule].
  static NotificationRule clampAndSanitizeRule(NotificationRule rule) {
    // Clamp priority: custom rules cannot assert critical
    String clampedPriority = rule.priority.toLowerCase();
    if (clampedPriority == 'critical' || clampedPriority.isEmpty) {
      clampedPriority = 'high';
    }

    // Sanitize conditions
    final sanitizedPackages = rule.conditions.packages
        .where((p) => p.trim().isNotEmpty && p.length <= maxStringLength)
        .take(maxPackages)
        .toList();

    final sanitizedKeywords = rule.conditions.keywords
        .where((k) => k.trim().length >= minKeywordLength && k.length <= maxStringLength)
        .take(maxKeywords)
        .toList();

    final sanitizedTitleKeywords = rule.conditions.titleKeywords
        .where((k) => k.trim().length >= minKeywordLength && k.length <= maxStringLength)
        .take(maxKeywords)
        .toList();

    return NotificationRule(
      id: rule.id.length > maxStringLength ? rule.id.substring(0, maxStringLength) : rule.id,
      category: rule.category,
      priority: clampedPriority,
      conditions: RuleCondition(
        packages: sanitizedPackages,
        keywords: sanitizedKeywords,
        titleKeywords: sanitizedTitleKeywords,
      ),
    );
  }

  /// Decodes and validates a raw list of JSON objects from storage.
  /// Discards corrupted or invalid entries, clamps priority, and enforces max 50 custom rules.
  static List<NotificationRule> validateAndSanitizeRules(List<dynamic> rawList) {
    final validRules = <NotificationRule>[];

    for (final rawItem in rawList) {
      if (rawItem is! Map) continue;
      final map = Map<String, dynamic>.from(rawItem);
      if (!isValidRuleMap(map)) continue;

      final rule = NotificationRule.fromMap(map);
      final sanitized = clampAndSanitizeRule(rule);

      // Verify that after sanitization, the rule still has conditions
      final hasCondition = sanitized.conditions.packages.isNotEmpty ||
          sanitized.conditions.keywords.isNotEmpty ||
          sanitized.conditions.titleKeywords.isNotEmpty;

      if (hasCondition) {
        validRules.add(sanitized);
      }

      if (validRules.length >= maxCustomRules) {
        break;
      }
    }

    return validRules;
  }
}
