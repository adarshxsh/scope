import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/models/notification_model.dart';

/// Result of rule schema validation.
class RuleValidationResult {
  final bool isValid;
  final String? error;

  const RuleValidationResult._(this.isValid, this.error);

  factory RuleValidationResult.valid() => const RuleValidationResult._(true, null);
  factory RuleValidationResult.invalid(String error) => RuleValidationResult._(false, error);
}

/// Schema validator for custom notification classification rules.
class RuleSchemaValidator {
  static const Set<String> reservedRuleIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
  };

  /// Validates the structure and condition bounds of a custom rule map.
  static RuleValidationResult validateCustomRule(Map<String, dynamic> map) {
    if (!map.containsKey('id') || map['id'] is! String || (map['id'] as String).trim().isEmpty) {
      return RuleValidationResult.invalid('Rule id must be a non-empty string.');
    }
    final id = (map['id'] as String).trim();
    if (reservedRuleIds.contains(id)) {
      return RuleValidationResult.invalid('Rule id "$id" is reserved for system security rules.');
    }

    if (!map.containsKey('category') || map['category'] is! String || (map['category'] as String).trim().isEmpty) {
      return RuleValidationResult.invalid('Rule category must be a non-empty string.');
    }

    if (!map.containsKey('priority') || map['priority'] is! String || (map['priority'] as String).trim().isEmpty) {
      return RuleValidationResult.invalid('Rule priority must be a non-empty string.');
    }

    if (!map.containsKey('conditions') || map['conditions'] is! Map) {
      return RuleValidationResult.invalid('Rule conditions must be a JSON object.');
    }

    final conditionsMap = Map<String, dynamic>.from(map['conditions'] as Map);

    if (conditionsMap.containsKey('packages') && conditionsMap['packages'] != null) {
      if (conditionsMap['packages'] is! Iterable) {
        return RuleValidationResult.invalid('packages condition must be a list.');
      }
      for (final item in conditionsMap['packages'] as Iterable) {
        if (item is! String) {
          return RuleValidationResult.invalid('packages items must be strings.');
        }
      }
    }

    if (conditionsMap.containsKey('keywords') && conditionsMap['keywords'] != null) {
      if (conditionsMap['keywords'] is! Iterable) {
        return RuleValidationResult.invalid('keywords condition must be a list.');
      }
      for (final item in conditionsMap['keywords'] as Iterable) {
        if (item is! String) {
          return RuleValidationResult.invalid('keywords items must be strings.');
        }
      }
    }

    final titleKey = conditionsMap.containsKey('title_keywords')
        ? 'title_keywords'
        : (conditionsMap.containsKey('titleKeywords') ? 'titleKeywords' : null);

    if (titleKey != null && conditionsMap[titleKey] != null) {
      if (conditionsMap[titleKey] is! Iterable) {
        return RuleValidationResult.invalid('$titleKey condition must be a list.');
      }
      for (final item in conditionsMap[titleKey] as Iterable) {
        if (item is! String) {
          return RuleValidationResult.invalid('$titleKey items must be strings.');
        }
      }
    }

    final packages = List<String>.from(conditionsMap['packages'] as Iterable? ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final keywords = List<String>.from(conditionsMap['keywords'] as Iterable? ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final titleKeywords = List<String>.from(
            (titleKey != null ? conditionsMap[titleKey] as Iterable? : null) ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (packages.isEmpty && keywords.isEmpty && titleKeywords.isEmpty) {
      return RuleValidationResult.invalid(
          'Custom rule must have at least one non-empty condition block.');
    }

    return RuleValidationResult.valid();
  }
}

/// Condition definition for a notification classification rule.
class RuleCondition {
  final List<String> packages;
  final List<String> keywords;
  final List<String> titleKeywords;

  const RuleCondition({
    this.packages = const [],
    this.keywords = const [],
    this.titleKeywords = const [],
  });

  factory RuleCondition.fromMap(Map<String, dynamic> map, {bool sanitize = false}) {
    final rawPackages = List<String>.from(map['packages'] as Iterable? ?? const []);
    final rawKeywords = List<String>.from(map['keywords'] as Iterable? ?? const []);
    final rawTitleKeywords = List<String>.from(
        map['title_keywords'] as Iterable? ?? map['titleKeywords'] as Iterable? ?? const []);

    if (!sanitize) {
      return RuleCondition(
        packages: rawPackages,
        keywords: rawKeywords,
        titleKeywords: rawTitleKeywords,
      );
    }

    return RuleCondition(
      packages: rawPackages.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      keywords: rawKeywords.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      titleKeywords: rawTitleKeywords.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packages': packages,
      'keywords': keywords,
      'title_keywords': titleKeywords,
    };
  }
}

/// A parsed match rule from JSON.
class NotificationRule {
  final String id;
  final String category;
  final String priority;
  final RuleCondition conditions;
  final bool isCustom;

  const NotificationRule({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditions,
    this.isCustom = false,
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map, {bool isCustom = false}) {
    final rawPriority = map['priority'] as String? ?? '';
    // Priority cap for custom rules: demote 'critical' to 'high'
    final finalPriority =
        (isCustom && rawPriority.toLowerCase() == 'critical') ? 'high' : rawPriority;

    return NotificationRule(
      id: map['id'] as String? ?? '',
      category: map['category'] as String? ?? '',
      priority: finalPriority,
      conditions: RuleCondition.fromMap(
        Map<String, dynamic>.from(map['conditions'] as Map? ?? const {}),
        sanitize: true,
      ),
      isCustom: isCustom,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'priority': priority,
      'conditions': conditions.toMap(),
    };
  }
}

/// The result returned by a successful rule engine match.
class MatchedRuleResult {
  final String ruleId;
  final String category;
  final String priority;
  final String matchedSignal;

  const MatchedRuleResult({
    required this.ruleId,
    required this.category,
    required this.priority,
    required this.matchedSignal,
  });

  @override
  String toString() => 'MatchedRuleResult(ruleId: $ruleId, category: $category, '
      'priority: $priority, matchedSignal: $matchedSignal)';
}

/// Compiled rule engine matching raw notifications against in-memory patterns.
class RuleEngine {
  String version = '0.0.0';
  List<NotificationRule> _systemRules = [];
  List<NotificationRule> _customRules = [];

  /// Combined list of rules (system rules first, followed by custom rules).
  List<NotificationRule> get rules => [..._systemRules, ..._customRules];

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map), isCustom: false))
        .toList();
  }

  /// Adds a user-defined reinforcement learning rule.
  /// Enforces priority capping to 'high' and validates non-empty condition bounds.
  void addReinforcementRule(NotificationRule rule) {
    final hasAnyCondition = rule.conditions.packages.any((p) => p.trim().isNotEmpty) ||
        rule.conditions.keywords.any((k) => k.trim().isNotEmpty) ||
        rule.conditions.titleKeywords.any((k) => k.trim().isNotEmpty);

    if (!hasAnyCondition) {
      throw ArgumentError('Custom rule must have at least one non-empty condition block.');
    }

    if (RuleSchemaValidator.reservedRuleIds.contains(rule.id)) {
      throw ArgumentError('Rule id "${rule.id}" is reserved for system security rules.');
    }

    final priority = rule.priority.toLowerCase() == 'critical' ? 'high' : rule.priority;

    final sanitizedConditions = RuleCondition(
      packages: rule.conditions.packages.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      keywords: rule.conditions.keywords.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      titleKeywords: rule.conditions.titleKeywords.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    );

    final customRule = NotificationRule(
      id: rule.id,
      category: rule.category,
      priority: priority,
      conditions: sanitizedConditions,
      isCustom: true,
    );

    _customRules.removeWhere((r) => r.id == customRule.id);
    _customRules.insert(0, customRule);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage. Validates schema and caps priority.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content);
        if (decoded is! List) {
          // ignore: avoid_print
          print('Custom rules storage is not a valid JSON list.');
          return;
        }

        final validRules = <NotificationRule>[];
        for (final item in decoded) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final valResult = RuleSchemaValidator.validateCustomRule(map);
            if (valResult.isValid) {
              validRules.add(NotificationRule.fromMap(map, isCustom: true));
            } else {
              // ignore: avoid_print
              print('Skipping invalid custom rule (${map['id']}): ${valResult.error}');
            }
          }
        }
        _customRules = validRules;
      }
    } catch (e) {
      // Safe fallback to base system rules
      // ignore: avoid_print
      print('Failed to load custom RLHF rules (falling back to base rules): $e');
    }
  }

  /// Saves all custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      final list = _customRules.map((r) => r.toMap()).toList();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save custom RLHF rules: $e');
    }
  }

  /// Helper to check if text matches a keyword pattern safely.
  /// Escapes regex control characters to prevent wildcard injection or invalid patterns.
  bool _matchKeyword(String text, String keyword) {
    if (keyword.isEmpty) return false;
    final lowerText = text.toLowerCase();
    final lowerKw = keyword.toLowerCase();

    try {
      final escapedPattern = RegExp.escape(lowerKw);
      return RegExp(escapedPattern, caseSensitive: false).hasMatch(lowerText);
    } catch (_) {
      return lowerText.contains(lowerKw);
    }
  }

  /// Scans the database to find the first rule matching this notification.
  /// Evaluates base system security rules before executing any custom user rules.
  MatchedRuleResult? match(AppNotification notification) {
    // 1. Evaluate system security rules first
    final systemMatch = _evaluateRuleList(_systemRules, notification);
    if (systemMatch != null) return systemMatch;

    // 2. Evaluate custom user/RLHF rules second
    final customMatch = _evaluateRuleList(_customRules, notification);
    if (customMatch != null) return customMatch;

    return null;
  }

  MatchedRuleResult? _evaluateRuleList(
      List<NotificationRule> rulesList, AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    for (final rule in rulesList) {
      // 1. Package match constraint
      final packageConditionMatches = rule.conditions.packages.isEmpty ||
          rule.conditions.packages.map((p) => p.toLowerCase()).contains(package);

      if (!packageConditionMatches) continue;

      // 2. Title keywords check with regex sanitization
      bool titleMatch = false;
      String? matchedTitleWord;
      if (rule.conditions.titleKeywords.isNotEmpty) {
        for (final word in rule.conditions.titleKeywords) {
          if (_matchKeyword(titleLower, word)) {
            titleMatch = true;
            matchedTitleWord = word;
            break;
          }
        }
      }

      // 3. Content keywords check with regex sanitization
      bool contentMatch = false;
      String? matchedContentWord;
      if (rule.conditions.keywords.isNotEmpty) {
        for (final word in rule.conditions.keywords) {
          if (_matchKeyword(contentLower, word)) {
            contentMatch = true;
            matchedContentWord = word;
            break;
          }
        }
      }

      final hasTitleCondition = rule.conditions.titleKeywords.isNotEmpty;
      final hasContentCondition = rule.conditions.keywords.isNotEmpty;

      final titleMatches = !hasTitleCondition || titleMatch;
      final contentMatches = !hasContentCondition || contentMatch;

      final hasAnyCondition =
          rule.conditions.packages.isNotEmpty || hasTitleCondition || hasContentCondition;

      if (hasAnyCondition && titleMatches && contentMatches) {
        final signals = <String>[];
        if (rule.conditions.packages.isNotEmpty) {
          signals.add('Package matched ($package)');
        }
        if (titleMatch) {
          signals.add('Title matches "$matchedTitleWord"');
        }
        if (contentMatch) {
          signals.add('Content matches "$matchedContentWord"');
        }

        return MatchedRuleResult(
          ruleId: rule.id,
          category: rule.category,
          priority: rule.priority,
          matchedSignal: signals.join(' AND '),
        );
      }
    }

    return null;
  }
}

