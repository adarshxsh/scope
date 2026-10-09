import 'package:scope/core/analysis/rule_engine.dart';

/// Validation result produced by [CustomRuleSchema.validate].
class ValidationResult {
  final bool isValid;
  final String? error;
  final NotificationRule? rule;

  const ValidationResult.success(this.rule)
      : isValid = true,
        error = null;

  const ValidationResult.failure(this.error)
      : isValid = false,
        rule = null;
}

/// JSON schema validation and sanitization for custom user-defined RLHF rules.
class CustomRuleSchema {
  static const int maxKeywordLength = 50;
  static const int maxKeywordsPerRule = 20;

  /// Validates input against schema limits and returns a sanitized [ValidationResult].
  static ValidationResult validate(dynamic input) {
    Map<String, dynamic> map;
    if (input is NotificationRule) {
      map = input.toMap();
    } else if (input is Map<String, dynamic>) {
      map = input;
    } else if (input is Map) {
      map = Map<String, dynamic>.from(input);
    } else {
      return const ValidationResult.failure('Invalid rule input format');
    }

    // 1. ID check
    final rawId = map['id']?.toString().trim() ?? '';
    if (rawId.isEmpty) {
      return const ValidationResult.failure('Rule ID must not be empty');
    }

    // 2. Category check
    final rawCategory = map['category']?.toString().trim() ?? '';

    // 3. Priority capping: Custom rules cannot claim 'critical' priority
    String priority = map['priority']?.toString().trim().toLowerCase() ?? 'medium';
    if (priority == 'critical') {
      priority = 'high';
    }

    // 4. Conditions check
    final rawConditions = map['conditions'];
    if (rawConditions == null || rawConditions is! Map) {
      return const ValidationResult.failure('Rule conditions are required');
    }

    final condMap = Map<String, dynamic>.from(rawConditions);
    final packages = List<String>.from(condMap['packages'] as Iterable? ?? const [])
        .map((e) => _sanitize(e))
        .where((e) => e.isNotEmpty)
        .toList();
    final keywords = List<String>.from(condMap['keywords'] as Iterable? ?? const [])
        .map((e) => _sanitize(e))
        .where((e) => e.isNotEmpty)
        .toList();
    final titleKeywords = List<String>.from(condMap['title_keywords'] as Iterable? ?? const [])
        .map((e) => _sanitize(e))
        .where((e) => e.isNotEmpty)
        .toList();

    // Required condition lists: Total conditions cannot be empty
    if (packages.isEmpty && keywords.isEmpty && titleKeywords.isEmpty) {
      return const ValidationResult.failure('Rule must contain at least one non-empty condition');
    }

    // Max keywords per rule limit (20 keywords max)
    final totalKeywords = keywords.length + titleKeywords.length;
    if (keywords.length > maxKeywordsPerRule ||
        titleKeywords.length > maxKeywordsPerRule ||
        totalKeywords > maxKeywordsPerRule) {
      return const ValidationResult.failure('Rule exceeds maximum keyword limit of 20 keywords');
    }

    // Max keyword length limit (50 characters max)
    for (final kw in [...keywords, ...titleKeywords]) {
      if (kw.length > maxKeywordLength) {
        return ValidationResult.failure('Keyword "$kw" exceeds maximum length of 50 characters');
      }
    }

    for (final pkg in packages) {
      if (pkg.length > maxKeywordLength) {
        return ValidationResult.failure('Package "$pkg" exceeds maximum length of 50 characters');
      }
    }

    final sanitizedRule = NotificationRule(
      id: rawId,
      category: rawCategory,
      priority: priority,
      conditions: RuleCondition(
        packages: packages,
        keywords: keywords,
        titleKeywords: titleKeywords,
      ),
      isSystemRule: false,
    );

    return ValidationResult.success(sanitizedRule);
  }

  static String _sanitize(String input) {
    return input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }
}
