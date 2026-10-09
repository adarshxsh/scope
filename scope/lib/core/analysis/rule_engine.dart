import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/rule_schema.dart';
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
  final bool isSystemRule;

  const NotificationRule({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditions,
    this.isSystemRule = false,
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map, {bool isSystemRule = false}) {
    return NotificationRule(
      id: map['id'] as String? ?? '',
      category: map['category'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      conditions: RuleCondition.fromMap(
        Map<String, dynamic>.from(map['conditions'] as Map? ?? const {}),
      ),
      isSystemRule: map['isSystemRule'] as bool? ?? isSystemRule,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'priority': priority,
      'conditions': conditions.toMap(),
      'isSystemRule': isSystemRule,
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

  const MatchedRuleResult({
    required this.ruleId,
    required this.category,
    required this.priority,
    required this.matchedSignal,
    this.isSystemRule = false,
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

  /// Returns the full list of active rules, prioritizing unmodifiable system rules first.
  List<NotificationRule> get activeRules => [..._systemRules, ..._customRules];

  /// Compiles a raw JSON rules database into compiled memory structures (system critical tier).
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];
    
    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(
              Map<String, dynamic>.from(r as Map),
              isSystemRule: true,
            ))
        .toList();
  }

  /// Validates payload against [CustomRuleSchema] and prepends custom RLHF rule.
  void addReinforcementRule(NotificationRule rule) {
    final validation = CustomRuleSchema.validate(rule);
    if (!validation.isValid || validation.rule == null) {
      throw ArgumentError('Invalid custom rule schema: ${validation.error}');
    }
    _customRules.insert(0, validation.rule!);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage, sanitizes & validates them, and populates custom tier.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content) as List<dynamic>;
        final loadedCustom = <NotificationRule>[];
        for (final item in list) {
          final validation = CustomRuleSchema.validate(item);
          if (validation.isValid && validation.rule != null) {
            loadedCustom.add(validation.rule!);
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

  /// Scans active rules to find the first rule matching this notification.
  /// System rules evaluate before custom rules.
  MatchedRuleResult? match(AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    for (final rule in activeRules) {
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
          isSystemRule: rule.isSystemRule,
        );
      }
    }

    return null;
  }
}
