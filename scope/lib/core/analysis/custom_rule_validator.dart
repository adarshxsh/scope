import 'package:scope/core/analysis/rule_engine.dart';

/// Schema validator and sanitizer for user-defined custom RLHF rules.
class CustomRuleValidator {
  /// Reserved system rule IDs that custom rules are forbidden from claiming.
  static const Set<String> reservedSystemIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
  };

  /// Max allowed custom rules in memory/storage.
  static const int maxCustomRules = 50;

  /// Max allowed keywords/packages per condition array.
  static const int maxConditionItems = 10;

  /// Max allowed string length per keyword/package string.
  static const int maxStringLength = 64;

  /// Validates and sanitizes a custom rule JSON map.
  /// Returns a valid [NotificationRule] with capped priority and enforced `rlhf-` prefix,
  /// or `null` if the rule structure violates schema constraints or claims reserved IDs.
  static NotificationRule? validateAndSanitizeMap(
    Map<String, dynamic> map, {
    Set<String>? systemRuleIds,
  }) {
    final rawId = map['id'] as String? ?? '';
    final id = rawId.trim();

    // ID Namespace enforcement: Must carry 'rlhf-' prefix
    if (!id.startsWith('rlhf-')) {
      return null;
    }

    // Reserved ID collision check
    final baseId = id.length > 5 ? id.substring(5) : '';
    if (reservedSystemIds.contains(id) ||
        reservedSystemIds.contains(baseId) ||
        (systemRuleIds != null && (systemRuleIds.contains(id) || systemRuleIds.contains(baseId)))) {
      return null;
    }

    // Priority Capping: Disallow 'critical' priority for custom rules
    String priority = (map['priority'] as String? ?? 'medium').trim().toLowerCase();
    if (priority == 'critical') {
      priority = 'high';
    }

    final category = (map['category'] as String? ?? 'custom').trim();

    final conditionsMap = map['conditions'];
    if (conditionsMap is! Map) {
      return null;
    }

    final sanitizedConditions = _sanitizeConditionsMap(
      Map<String, dynamic>.from(conditionsMap),
    );

    if (sanitizedConditions == null) {
      return null;
    }

    return NotificationRule(
      id: id,
      category: category,
      priority: priority,
      conditions: sanitizedConditions,
    );
  }

  /// Validates and sanitizes an in-memory [NotificationRule] instance.
  /// Enforces `rlhf-` prefix, reserved ID checks, priority capping, and condition bounds.
  static NotificationRule? validateAndSanitizeRule(
    NotificationRule rule, {
    Set<String>? systemRuleIds,
  }) {
    final id = rule.id.trim();
    if (!id.startsWith('rlhf-')) {
      return null;
    }

    // Reserved ID collision check
    final baseId = id.length > 5 ? id.substring(5) : '';
    if (reservedSystemIds.contains(id) ||
        reservedSystemIds.contains(baseId) ||
        (systemRuleIds != null && (systemRuleIds.contains(id) || systemRuleIds.contains(baseId)))) {
      return null;
    }

    // Priority Capping
    var priority = rule.priority.trim().toLowerCase();
    if (priority == 'critical') {
      priority = 'high';
    }

    final sanitizedConditions = _sanitizeRuleCondition(rule.conditions);
    if (sanitizedConditions == null) {
      return null;
    }

    return NotificationRule(
      id: id,
      category: rule.category.trim().isEmpty ? 'custom' : rule.category,
      priority: priority.isEmpty ? 'medium' : priority,
      conditions: sanitizedConditions,
    );
  }

  static RuleCondition? _sanitizeConditionsMap(Map<String, dynamic> map) {
    final rawPackages = map['packages'] as Iterable? ?? const [];
    final rawKeywords = map['keywords'] as Iterable? ?? const [];
    final rawTitleKeywords = map['title_keywords'] as Iterable? ?? const [];

    final packages = _cleanStringList(rawPackages);
    final keywords = _cleanStringList(rawKeywords);
    final titleKeywords = _cleanStringList(rawTitleKeywords);

    // Schema constraint: Custom rule must have at least one non-empty condition signal
    if (packages.isEmpty && keywords.isEmpty && titleKeywords.isEmpty) {
      return null;
    }

    return RuleCondition(
      packages: packages,
      keywords: keywords,
      titleKeywords: titleKeywords,
    );
  }

  static RuleCondition? _sanitizeRuleCondition(RuleCondition condition) {
    final packages = _cleanStringList(condition.packages);
    final keywords = _cleanStringList(condition.keywords);
    final titleKeywords = _cleanStringList(condition.titleKeywords);

    if (packages.isEmpty && keywords.isEmpty && titleKeywords.isEmpty) {
      return null;
    }

    return RuleCondition(
      packages: packages,
      keywords: keywords,
      titleKeywords: titleKeywords,
    );
  }

  static List<String> _cleanStringList(Iterable raw) {
    final result = <String>[];
    for (final item in raw) {
      if (item != null) {
        var str = item.toString().trim();
        if (str.isNotEmpty) {
          if (str.length > maxStringLength) {
            str = str.substring(0, maxStringLength);
          }
          result.add(str);
          if (result.length >= maxConditionItems) break;
        }
      }
    }
    return result;
  }
}
