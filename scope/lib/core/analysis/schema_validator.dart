/// Result of a custom rule schema validation check.
class SchemaValidationResult {
  final bool isValid;
  final String? error;

  const SchemaValidationResult.valid()
      : isValid = true,
        error = null;

  const SchemaValidationResult.invalid(this.error)
      : isValid = false;

  @override
  String toString() => isValid ? 'SchemaValidationResult.valid()' : 'SchemaValidationResult.invalid($error)';
}

/// Strict schema validator for custom RLHF rules.
class SchemaValidator {
  static const Set<String> _reservedRuleIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
    'family_urgent',
    'work_collaboration',
    'medical_reminder',
    'promo_deals',
    'social_engagement',
  };

  static const Set<String> _permittedPriorities = {
    'high',
    'medium',
    'low',
  };

  static const Set<String> _permittedCategories = {
    'sys',
    'finance',
    'scholarship',
    'msg',
    'health',
    'promo',
    'social',
  };

  static const int _maxIdLength = 64;
  static const int _maxCategoryLength = 32;
  static const int _maxPriorityLength = 16;
  static const int _maxConditionItemLength = 128;

  /// Validates a custom rule payload against strict structural and security constraints.
  static SchemaValidationResult validateCustomRule(dynamic payload) {
    if (payload is! Map) {
      return const SchemaValidationResult.invalid('Payload must be a Map structure');
    }

    final map = Map<String, dynamic>.from(payload);

    // 1. Validate ID
    final idRaw = map['id'];
    if (idRaw is! String) {
      return const SchemaValidationResult.invalid('Rule ID must be a non-null String');
    }
    final id = idRaw.trim();
    if (id.isEmpty) {
      return const SchemaValidationResult.invalid('Rule ID cannot be empty');
    }
    if (id.length > _maxIdLength) {
      return SchemaValidationResult.invalid('Rule ID exceeds max length of $_maxIdLength characters');
    }
    if (_reservedRuleIds.contains(id)) {
      return SchemaValidationResult.invalid('Rule ID "$id" is a reserved system rule ID');
    }
    if (!id.startsWith('rlhf-')) {
      return const SchemaValidationResult.invalid('Custom rule ID must start with "rlhf-" prefix');
    }

    // 2. Validate Priority
    final priorityRaw = map['priority'];
    if (priorityRaw is! String) {
      return const SchemaValidationResult.invalid('Rule priority must be a non-null String');
    }
    final priority = priorityRaw.trim().toLowerCase();
    if (priority.length > _maxPriorityLength) {
      return SchemaValidationResult.invalid('Priority exceeds max length of $_maxPriorityLength characters');
    }
    if (priority == 'critical') {
      return const SchemaValidationResult.invalid('Custom rules are prohibited from setting "critical" priority');
    }
    if (!_permittedPriorities.contains(priority)) {
      return SchemaValidationResult.invalid('Priority "$priority" is not a permitted priority value. Allowed: $_permittedPriorities');
    }

    // 3. Validate Category
    final categoryRaw = map['category'];
    if (categoryRaw is! String) {
      return const SchemaValidationResult.invalid('Rule category must be a non-null String');
    }
    final category = categoryRaw.trim().toLowerCase();
    if (category.length > _maxCategoryLength) {
      return SchemaValidationResult.invalid('Category exceeds max length of $_maxCategoryLength characters');
    }
    if (!_permittedCategories.contains(category)) {
      return SchemaValidationResult.invalid('Category "$category" is not a permitted category. Allowed: $_permittedCategories');
    }

    // 4. Validate Conditions
    final conditionsRaw = map['conditions'];
    if (conditionsRaw is! Map) {
      return const SchemaValidationResult.invalid('Rule conditions must be a Map structure');
    }
    final conditions = Map<String, dynamic>.from(conditionsRaw);

    int totalConditionItems = 0;

    // Validate packages
    if (conditions.containsKey('packages')) {
      final packagesRaw = conditions['packages'];
      final res = _validateConditionList(packagesRaw, 'packages');
      if (!res.isValid) return SchemaValidationResult.invalid(res.error);
      totalConditionItems += res.count;
    }

    // Validate keywords
    if (conditions.containsKey('keywords')) {
      final keywordsRaw = conditions['keywords'];
      final res = _validateConditionList(keywordsRaw, 'keywords');
      if (!res.isValid) return SchemaValidationResult.invalid(res.error);
      totalConditionItems += res.count;
    }

    // Validate title_keywords or titleKeywords
    final titleKeywordsRaw = conditions['title_keywords'] ?? conditions['titleKeywords'];
    if (titleKeywordsRaw != null) {
      final res = _validateConditionList(titleKeywordsRaw, 'title_keywords');
      if (!res.isValid) return SchemaValidationResult.invalid(res.error);
      totalConditionItems += res.count;
    }

    if (totalConditionItems == 0) {
      return const SchemaValidationResult.invalid('Conditions must contain at least one non-empty package, keyword, or title keyword');
    }

    return const SchemaValidationResult.valid();
  }

  /// Helper to check if custom rule payload is valid.
  static bool isValidCustomRulePayload(dynamic payload) {
    return validateCustomRule(payload).isValid;
  }

  static _ConditionListResult _validateConditionList(dynamic rawList, String fieldName) {
    if (rawList is! Iterable) {
      return _ConditionListResult.invalid('$fieldName must be a List');
    }
    int validCount = 0;
    for (final item in rawList) {
      if (item is! String) {
        return _ConditionListResult.invalid('$fieldName items must all be Strings');
      }
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        return _ConditionListResult.invalid('$fieldName items cannot be empty strings');
      }
      if (trimmed.length > _maxConditionItemLength) {
        return _ConditionListResult.invalid('$fieldName item "$trimmed" exceeds max length of $_maxConditionItemLength characters');
      }
      validCount++;
    }
    return _ConditionListResult.valid(validCount);
  }
}

class _ConditionListResult {
  final bool isValid;
  final String? error;
  final int count;

  const _ConditionListResult.valid(this.count)
      : isValid = true,
        error = null;

  const _ConditionListResult.invalid(this.error)
      : isValid = false,
        count = 0;
}
