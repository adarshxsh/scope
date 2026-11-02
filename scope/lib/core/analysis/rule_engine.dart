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

/// Two-tier compiled rule engine matching raw notifications against system and custom rules.
class RuleEngine {
  String version = '0.0.0';
  List<NotificationRule> _systemRules = [];
  List<NotificationRule> _customRules = [];

  /// Maximum allowed custom rules stored/evaluated.
  static const int maxCustomRules = 50;

  /// Unmodifiable view of loaded system rules (Tier 1).
  List<NotificationRule> get systemRules => List.unmodifiable(_systemRules);

  /// Unmodifiable view of loaded custom rules (Tier 2).
  List<NotificationRule> get customRules => List.unmodifiable(_customRules);

  /// All rules in evaluation order (System Tier 1 followed by Custom Tier 2).
  List<NotificationRule> get rules => List.unmodifiable([..._systemRules, ..._customRules]);

  /// Compiles system base rules from JSON database.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Adds or updates a user-defined custom rule in the Tier 2 custom rule set.
  /// Validates and sanitizes the rule schema before storing.
  bool addReinforcementRule(NotificationRule rule) {
    final systemRuleIds = _systemRules.map((r) => r.id).toSet();
    final sanitizedRule = CustomRuleValidator.validateAndSanitize(
      rule,
      systemRuleIds: systemRuleIds,
    );

    if (sanitizedRule == null) {
      // ignore: avoid_print
      print('RuleEngine: Rejected invalid custom rule "${rule.id}".');
      return false;
    }

    final existingIndex = _customRules.indexWhere((r) => r.id == sanitizedRule.id);
    if (existingIndex >= 0) {
      _customRules[existingIndex] = sanitizedRule;
    } else {
      _customRules.insert(0, sanitizedRule);
    }

    if (_customRules.length > maxCustomRules) {
      _customRules = _customRules.sublist(0, maxCustomRules);
    }

    _saveCustomRules();
    return true;
  }

  /// Loads custom user rules from local storage into Tier 2.
  /// Logs and skips malformed or invalid custom rule entries without crashing.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content);
        if (list is! List) {
          // ignore: avoid_print
          print('RuleEngine: Malformed rlhf_rules.json - expected a JSON list.');
          return;
        }

        final systemRuleIds = _systemRules.map((r) => r.id).toSet();
        final loadedCustomRules = <NotificationRule>[];

        for (final item in list) {
          if (loadedCustomRules.length >= maxCustomRules) break;

          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final validRule = CustomRuleValidator.validateAndSanitizeMap(
              map,
              systemRuleIds: systemRuleIds,
            );
            if (validRule != null) {
              loadedCustomRules.add(validRule);
            } else {
              // ignore: avoid_print
              print('RuleEngine: Skipping invalid custom rule entry: $item');
            }
          } else {
            // ignore: avoid_print
            print('RuleEngine: Skipping malformed custom rule entry (not a map): $item');
          }
        }

        _customRules = loadedCustomRules;
      }
    } catch (e) {
      // ignore: avoid_print
      print('RuleEngine: Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      final list = _customRules.take(maxCustomRules).map((r) => r.toMap()).toList();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));
    } catch (e) {
      // ignore: avoid_print
      print('RuleEngine: Failed to save custom RLHF rules: $e');
    }
  }

  /// Evaluates notification against rules in strict two-tier order:
  /// Tier 1: System Base Rules execute first.
  /// Tier 2: Custom User Rules execute only if no system rule matches.
  MatchedRuleResult? match(AppNotification notification) {
    // Tier 1: System Rules
    final systemMatch = _evaluateRuleList(notification, _systemRules, isSystemTier: true);
    if (systemMatch != null) return systemMatch;

    // Tier 2: Custom Rules
    final customMatch = _evaluateRuleList(notification, _customRules, isSystemTier: false);
    if (customMatch != null) return customMatch;

    return null;
  }

  MatchedRuleResult? _evaluateRuleList(
    AppNotification notification,
    List<NotificationRule> ruleList, {
    required bool isSystemTier,
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
          isSystemRule: isSystemTier,
        );
      }
    }

    return null;
  }
}

