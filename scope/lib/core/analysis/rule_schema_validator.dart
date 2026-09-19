import 'package:scope/core/analysis/rule_engine.dart';

/// Validation exception thrown when a rule definition fails schema checks.
class RuleSchemaValidationException implements Exception {
  final String message;
  final String? ruleId;

  const RuleSchemaValidationException(this.message, [this.ruleId]);

  @override
  String toString() =>
      'RuleSchemaValidationException: $message${ruleId != null ? ' (ruleId: $ruleId)' : ''}';
}

/// Validates rule schema, sanitizes condition terms, and enforces priority guardrails.
class RuleSchemaValidator {
  static const Set<String> reservedSystemRuleIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
  };

  /// Sanitizes condition keyword terms using RegExp.escape to prevent regex injection errors.
  static List<String> sanitizeKeywords(List<String> keywords) {
    return keywords.map((k) => RegExp.escape(k.trim())).where((k) => k.isNotEmpty).toList();
  }

  /// Sanitizes a raw condition map.
  static RuleCondition sanitizeCondition(RuleCondition condition) {
    return RuleCondition(
      packages: condition.packages.map((p) => p.trim().toLowerCase()).where((p) => p.isNotEmpty).toList(),
      keywords: sanitizeKeywords(condition.keywords),
      titleKeywords: sanitizeKeywords(condition.titleKeywords),
    );
  }

  /// Validates a single rule object.
  /// Enforces non-empty conditions and demotes custom user rule priorities if critical.
  static NotificationRule validateAndSanitize(
    NotificationRule rule, {
    bool isCustomUserRule = false,
  }) {
    if (rule.id.trim().isEmpty) {
      throw const RuleSchemaValidationException('Rule ID cannot be empty.');
    }

    final sanitizedCondition = sanitizeCondition(rule.conditions);

    // Enforce non-empty condition block (at least one condition must be specified)
    if (sanitizedCondition.packages.isEmpty &&
        sanitizedCondition.keywords.isEmpty &&
        sanitizedCondition.titleKeywords.isEmpty) {
      throw RuleSchemaValidationException(
        'Rule must contain at least one non-empty package, keyword, or title_keyword condition.',
        rule.id,
      );
    }

    String adjustedPriority = rule.priority.toLowerCase();

    // Guardrail: Custom user rules cannot claim 'critical' priority to prevent unverified overrides
    if (isCustomUserRule || rule.id.startsWith('rlhf-')) {
      if (adjustedPriority == 'critical') {
        adjustedPriority = 'high';
      }
    }

    return NotificationRule(
      id: rule.id,
      category: rule.category.isEmpty ? 'uncategorized' : rule.category,
      priority: adjustedPriority,
      conditions: sanitizedCondition,
    );
  }

  /// Validates a list of rules.
  static List<NotificationRule> validateRuleList(
    List<NotificationRule> rules, {
    bool isCustomUserRule = false,
  }) {
    final validated = <NotificationRule>[];
    for (final r in rules) {
      try {
        validated.add(validateAndSanitize(r, isCustomUserRule: isCustomUserRule));
      } catch (e) {
        // Skip invalid rules gracefully
      }
    }
    return validated;
  }
}
