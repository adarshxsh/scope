import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/custom_rule_validator.dart';
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
}

/// The result returned by a successful rule engine match.
class MatchedRuleResult {
  final String ruleId;
  final String category;
  final String priority;
  final String matchedSignal;
  final bool isSystemRule;

  bool get isCustom => !isSystemRule;

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

/// Compiled rule engine matching raw notifications against in-memory patterns using a two-tier architecture.
class RuleEngine {
  String version = '0.0.0';

  /// Immutable Tier-1 System Security Rules
  List<NotificationRule> _systemRules = [];

  /// User-defined Tier-2 Custom RLHF Rules
  List<NotificationRule> _customRules = [];

  List<NotificationRule> get systemRules => List.unmodifiable(_systemRules);
  List<NotificationRule> get customRules => List.unmodifiable(_customRules);
  List<NotificationRule> get rules => [..._systemRules, ..._customRules];

  /// Compiles a raw JSON rules database into compiled memory structures (Tier-1 system security rules).
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Prepends a user-defined reinforcement learning rule into Tier-2 custom evaluation chain.
  /// Validates and sanitizes rule structure, enforcing `rlhf-` ID prefix, priority capping, and reserved ID restrictions.
  void addReinforcementRule(NotificationRule rule) {
    final systemIds = _systemRules.map((r) => r.id).toSet();
    final sanitized = CustomRuleValidator.validateAndSanitizeRule(
      rule,
      systemRuleIds: systemIds,
    );
    if (sanitized == null) {
      throw ArgumentError('Custom rule failed schema validation or ID namespace enforcement.');
    }
    _customRules.insert(0, sanitized);
    if (_customRules.length > CustomRuleValidator.maxCustomRules) {
      _customRules = _customRules.sublist(0, CustomRuleValidator.maxCustomRules);
    }
    _saveCustomRules();
  }

  /// Loads custom RLHF rules from local storage into Tier-2, validating schema, capping priority,
  /// and enforcing `rlhf-` ID namespace. Rewrites corrupt/malformed files to '[]' for state recovery.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        dynamic parsed;
        try {
          parsed = json.decode(content);
        } catch (e) {
          // Malformed JSON -> automatic state recovery
          await file.writeAsString('[]');
          _customRules = [];
          return;
        }

        if (parsed is! List) {
          await file.writeAsString('[]');
          _customRules = [];
          return;
        }

        final systemIds = _systemRules.map((r) => r.id).toSet();
        final loadedCustomRules = <NotificationRule>[];

        for (final item in parsed) {
          if (item is Map) {
            final sanitized = CustomRuleValidator.validateAndSanitizeMap(
              Map<String, dynamic>.from(item),
              systemRuleIds: systemIds,
            );
            if (sanitized != null) {
              loadedCustomRules.add(sanitized);
            }
          }
        }

        if (loadedCustomRules.length > CustomRuleValidator.maxCustomRules) {
          _customRules = loadedCustomRules.sublist(0, CustomRuleValidator.maxCustomRules);
        } else {
          _customRules = loadedCustomRules;
        }
      } else {
        _customRules = [];
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
      _customRules = [];
    }
  }

  /// Saves all active Tier-2 custom RLHF rules to local storage.
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

  /// Scans Tier-1 system rules first, then Tier-2 custom rules to find the first rule matching this notification.
  /// Tier-1 system rules always execute prior to any Tier-2 custom rules.
  /// Returns a [MatchedRuleResult] if a match is found, or null otherwise.
  MatchedRuleResult? match(AppNotification notification) {
    // Phase 1: Tier-1 System Security Rules Evaluation
    final systemMatch = _evaluateRuleList(_systemRules, notification, isSystemRule: true);
    if (systemMatch != null) {
      return systemMatch;
    }

    // Phase 2: Tier-2 Custom RLHF Rules Evaluation
    final customMatch = _evaluateRuleList(_customRules, notification, isSystemRule: false);
    if (customMatch != null) {
      return customMatch;
    }

    return null;
  }

  MatchedRuleResult? _evaluateRuleList(
    List<NotificationRule> ruleList,
    AppNotification notification, {
    required bool isSystemRule,
  }) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    for (final rule in ruleList) {
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

