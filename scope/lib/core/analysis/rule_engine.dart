import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/models/notification_model.dart';

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

  factory RuleCondition.fromMap(Map<String, dynamic> map) {
    return RuleCondition(
      packages: List<String>.from(map['packages'] as Iterable? ?? const []),
      keywords: List<String>.from(map['keywords'] as Iterable? ?? const []),
      titleKeywords: List<String>.from(map['title_keywords'] as Iterable? ?? const []),
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

  const NotificationRule({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditions,
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map) {
    return NotificationRule(
      id: map['id'] as String? ?? '',
      category: map['category'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      conditions: RuleCondition.fromMap(
        Map<String, dynamic>.from(map['conditions'] as Map? ?? const {}),
      ),
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

  /// Validates and sanitizes a custom rule.
  /// Returns a sanitized [NotificationRule] if valid, or null if malformed/invalid.
  static NotificationRule? validateAndSanitizeCustomRule(NotificationRule rule) {
    if (rule.id.trim().isEmpty || !rule.id.trim().startsWith('rlhf-')) {
      return null;
    }
    if (rule.category.trim().isEmpty) {
      return null;
    }
    if (rule.priority.trim().isEmpty) {
      return null;
    }

    // Priority Ceiling Enforcement:
    // Custom rules setting 'critical' priority are automatically demoted to 'high'
    String priority = rule.priority.toLowerCase().trim();
    if (priority == 'critical') {
      priority = 'high';
    } else if (priority != 'high' && priority != 'medium' && priority != 'low') {
      return null;
    }

    // Condition Sanitization
    final sanitizedPackages = rule.conditions.packages
        .map((p) => p.trim())
        .where((p) => p.length > 1 && p != '*' && p != '?')
        .toList();

    final sanitizedTitleKeywords = rule.conditions.titleKeywords
        .map((k) => k.trim())
        .where((k) => k.length > 1 && k != '*' && k != '?')
        .toList();

    final sanitizedKeywords = rule.conditions.keywords
        .map((k) => k.trim())
        .where((k) => k.length > 1 && k != '*' && k != '?')
        .toList();

    // Reject empty condition definitions (must have at least one valid package, titleKeyword, or keyword)
    if (sanitizedPackages.isEmpty &&
        sanitizedTitleKeywords.isEmpty &&
        sanitizedKeywords.isEmpty) {
      return null;
    }

    return NotificationRule(
      id: rule.id.trim(),
      category: rule.category.trim(),
      priority: priority,
      conditions: RuleCondition(
        packages: sanitizedPackages,
        titleKeywords: sanitizedTitleKeywords,
        keywords: sanitizedKeywords,
      ),
    );
  }
}

/// The result returned by a successful rule engine match.
class MatchedRuleResult {
  final String ruleId;
  final String category;
  final String priority;
  final String matchedSignal;
  final bool isSystemRule;

  const MatchedRuleResult({
    required this.ruleId,
    required this.category,
    required this.priority,
    required this.matchedSignal,
    this.isSystemRule = true,
  });

  @override
  String toString() => 'MatchedRuleResult(ruleId: $ruleId, category: $category, '
      'priority: $priority, matchedSignal: $matchedSignal, isSystemRule: $isSystemRule)';
}

/// Compiled rule engine matching raw notifications against in-memory patterns.
class RuleEngine {
  String version = '0.0.0';
  List<NotificationRule> _systemRules = [];
  List<NotificationRule> _customRules = [];

  /// Combined getter for all active rules (system rules followed by custom rules).
  List<NotificationRule> get rules => [..._systemRules, ..._customRules];
  List<NotificationRule> get systemRules => List.unmodifiable(_systemRules);
  List<NotificationRule> get customRules => List.unmodifiable(_customRules);

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Validates and prepends a user-defined reinforcement learning rule to the top of the custom rule evaluation chain.
  bool addReinforcementRule(NotificationRule rule) {
    final sanitized = NotificationRule.validateAndSanitizeCustomRule(rule);
    if (sanitized == null) {
      // ignore: avoid_print
      print('RuleEngine: Rejected invalid custom rule "${rule.id}".');
      return false;
    }
    _customRules.removeWhere((r) => r.id == sanitized.id);
    _customRules.insert(0, sanitized);
    _saveCustomRules();
    return true;
  }

  /// Loads custom rules from local storage, validating each rule through schema validator.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content) as List<dynamic>;
        final List<NotificationRule> loadedCustom = [];
        for (final r in list) {
          if (r is Map) {
            final rule = NotificationRule.fromMap(Map<String, dynamic>.from(r));
            final sanitized = NotificationRule.validateAndSanitizeCustomRule(rule);
            if (sanitized != null) {
              loadedCustom.add(sanitized);
            } else {
              // ignore: avoid_print
              print('RuleEngine: Rejected malformed custom rule "${rule.id}" from storage.');
            }
          }
        }
        _customRules = loadedCustom;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
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

  /// Scans system rules first, then custom rules to find the first rule matching this notification.
  /// Returns a [MatchedRuleResult] if a match is found, or null otherwise.
  MatchedRuleResult? match(AppNotification notification) {
    // 1. Evaluate system security rules chain first
    final systemMatch = _matchInChain(_systemRules, notification, isSystemRule: true);
    if (systemMatch != null) {
      return systemMatch;
    }

    // 2. Evaluate custom user rules chain second
    final customMatch = _matchInChain(_customRules, notification, isSystemRule: false);
    if (customMatch != null) {
      return customMatch;
    }

    return null;
  }

  MatchedRuleResult? _matchInChain(
    List<NotificationRule> chain,
    AppNotification notification, {
    required bool isSystemRule,
  }) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    for (final rule in chain) {
      // 1. Package match constraint
      final packageConditionMatches =
          rule.conditions.packages.isEmpty || rule.conditions.packages.contains(package);

      if (!packageConditionMatches) continue;

      // 2. Title keywords check
      bool titleMatch = false;
      String? matchedTitleWord;
      if (rule.conditions.titleKeywords.isNotEmpty) {
        for (final word in rule.conditions.titleKeywords) {
          if (titleLower.contains(word.toLowerCase())) {
            titleMatch = true;
            matchedTitleWord = word;
            break;
          }
        }
      }

      // 3. Content keywords check
      bool contentMatch = false;
      String? matchedContentWord;
      if (rule.conditions.keywords.isNotEmpty) {
        for (final word in rule.conditions.keywords) {
          if (contentLower.contains(word.toLowerCase())) {
            contentMatch = true;
            matchedContentWord = word;
            break;
          }
        }
      }

      // Evaluation criteria:
      // If a rule lists title keywords, the title must match.
      // If a rule lists content keywords, the content must match.
      // If both are present, both must match (AND relationship).
      final hasTitleCondition = rule.conditions.titleKeywords.isNotEmpty;
      final hasContentCondition = rule.conditions.keywords.isNotEmpty;

      final titleMatches = !hasTitleCondition || titleMatch;
      final contentMatches = !hasContentCondition || contentMatch;

      // Check if at least one condition was configured
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
          isSystemRule: isSystemRule,
        );
      }
    }

    return null;
  }
}
