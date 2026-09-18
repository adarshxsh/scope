import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/schema_validator.dart';
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
  final bool isCustom;

  const NotificationRule({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditions,
    this.isCustom = false,
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map, {bool isCustom = false}) {
    return NotificationRule(
      id: map['id'] as String? ?? '',
      category: map['category'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      conditions: RuleCondition.fromMap(
        Map<String, dynamic>.from(map['conditions'] as Map? ?? const {}),
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
  final bool isCustom;

  const MatchedRuleResult({
    required this.ruleId,
    required this.category,
    required this.priority,
    required this.matchedSignal,
    this.isCustom = false,
  });

  @override
  String toString() => 'MatchedRuleResult(ruleId: $ruleId, category: $category, '
      'priority: $priority, matchedSignal: $matchedSignal, isCustom: $isCustom)';
}

/// Compiled rule engine matching raw notifications against in-memory patterns.
class RuleEngine {
  String version = '0.0.0';
  List<NotificationRule> _systemRules = [];
  final List<NotificationRule> _customRules = [];

  /// Combined rules list (pre-compiled system rules followed by dynamic custom rules).
  List<NotificationRule> get rules => List.unmodifiable([..._systemRules, ..._customRules]);

  /// Pre-compiled system base rules.
  List<NotificationRule> get systemRules => List.unmodifiable(_systemRules);

  /// Dynamic custom RLHF rules.
  List<NotificationRule> get customRules => List.unmodifiable(_customRules);

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];
    
    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map), isCustom: false))
        .toList();
  }

  /// Adds a user-defined reinforcement learning rule after strict schema validation.
  void addReinforcementRule(NotificationRule rule) {
    final map = rule.toMap();
    final validation = SchemaValidator.validateCustomRule(map);
    if (!validation.isValid) {
      debugPrint('Rejected invalid reinforcement rule "${rule.id}": ${validation.error}');
      return;
    }

    final validatedRule = NotificationRule(
      id: rule.id,
      category: rule.category,
      priority: rule.priority,
      conditions: rule.conditions,
      isCustom: true,
    );

    _customRules.insert(0, validatedRule);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage after validating each entry against the schema.
  Future<void> loadCustomRules() async {
    _customRules.clear();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic parsedJson = json.decode(content);
        if (parsedJson is List) {
          for (final raw in parsedJson) {
            final validation = SchemaValidator.validateCustomRule(raw);
            if (validation.isValid) {
              final customRule = NotificationRule.fromMap(
                Map<String, dynamic>.from(raw as Map),
                isCustom: true,
              );
              _customRules.add(customRule);
            } else {
              debugPrint('Discarded invalid custom rule entry: ${validation.error}');
            }
          }
        } else {
          debugPrint('rlhf_rules.json root is not a List. Discarding content.');
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom RLHF rules safely: $e');
    }
  }

  /// Saves all dynamic custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      final list = _customRules.map((r) => r.toMap()).toList();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));
    } catch (e) {
      debugPrint('Failed to save custom RLHF rules: $e');
    }
  }

  /// Scans the database to find the first rule matching this notification.
  /// Pre-compiled system rules retain precedence over dynamic custom rules.
  MatchedRuleResult? match(AppNotification notification) {
    // 1. Evaluate system base rules first (higher priority / immutable precedence)
    for (final rule in _systemRules) {
      final matchResult = _evaluateRule(rule, notification);
      if (matchResult != null) return matchResult;
    }

    // 2. Evaluate secondary custom RLHF rules
    for (final rule in _customRules) {
      final matchResult = _evaluateRule(rule, notification);
      if (matchResult != null) return matchResult;
    }

    return null;
  }

  MatchedRuleResult? _evaluateRule(NotificationRule rule, AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    // 1. Package match constraint
    final packageConditionMatches =
        rule.conditions.packages.isEmpty || rule.conditions.packages.contains(package);

    if (!packageConditionMatches) return null;

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
        isCustom: rule.isCustom,
      );
    }

    return null;
  }
}

