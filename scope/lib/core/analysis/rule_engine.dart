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
  final bool isCustom;

  const NotificationRule({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditions,
    this.isCustom = false,
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map, {bool isCustom = false}) {
    final idStr = map['id'] as String? ?? '';
    final customFlag = isCustom ||
        (map['is_custom'] as bool? ?? false) ||
        idStr.startsWith('rlhf-') ||
        idStr.startsWith('custom-');

    return NotificationRule(
      id: idStr,
      category: map['category'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      conditions: RuleCondition.fromMap(
        Map<String, dynamic>.from(map['conditions'] as Map? ?? const {}),
      ),
      isCustom: customFlag,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'priority': priority,
      'conditions': conditions.toMap(),
      'is_custom': isCustom,
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

  bool get isSystemRule => !isCustom;

  @override
  String toString() => 'MatchedRuleResult(ruleId: $ruleId, category: $category, '
      'priority: $priority, matchedSignal: $matchedSignal, isCustom: $isCustom)';
}

/// Compiled rule engine matching raw notifications against in-memory patterns.
class RuleEngine {
  String version = '0.0.0';
  List<NotificationRule> _systemRules = [];
  List<NotificationRule> _customRules = [];

  List<NotificationRule> get rules => [..._systemRules, ..._customRules];

  /// Compiles a raw JSON rules database into Tier 1 system rules.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map), isCustom: false))
        .toList();
  }

  /// Prepends a user-defined reinforcement learning rule to the top of Tier 2 custom rules.
  void addReinforcementRule(NotificationRule rule) {
    final sanitized = CustomRuleValidator.validateAndSanitizeRule(rule);
    if (sanitized == null) {
      return; // Discard invalid or malformed rule
    }

    _customRules.insert(0, sanitized);
    if (_customRules.length > CustomRuleValidator.maxCustomRules) {
      _customRules = _customRules.take(CustomRuleValidator.maxCustomRules).toList();
    }
    _saveCustomRules();
  }

  /// Loads custom rules synchronously during startup from local storage.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content) as List<dynamic>;
        _customRules = CustomRuleValidator.validateCustomRuleList(list);

        // Rewrite cleaned rules to local storage
        await file.writeAsString(json.encode(_customRules.map((r) => r.toMap()).toList()));
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
      _customRules = [];
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/rlhf_rules.json');
        if (await file.exists()) {
          await file.writeAsString('[]');
        }
      } catch (_) {}
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

  /// Scans the database to find the first rule matching this notification.
  /// Tier 1 base system rules are evaluated first.
  /// Tier 2 custom user rules are evaluated second.
  MatchedRuleResult? match(AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    // 1. Evaluate Tier 1 System Rules first
    final systemMatch = _evaluateRules(_systemRules, titleLower, contentLower, package);
    if (systemMatch != null) return systemMatch;

    // 2. Evaluate Tier 2 Custom User Rules second
    return _evaluateRules(_customRules, titleLower, contentLower, package);
  }

  MatchedRuleResult? _evaluateRules(
    List<NotificationRule> ruleList,
    String titleLower,
    String contentLower,
    String package,
  ) {
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
          isCustom: rule.isCustom,
        );
      }
    }

    return null;
  }
}
