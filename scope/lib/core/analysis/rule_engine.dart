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
    final id = map['id'] as String? ?? '';
    var priority = map['priority'] as String? ?? '';
    if (id.startsWith('rlhf-') && priority.toLowerCase() == 'critical') {
      priority = 'high';
    }
    return NotificationRule(
      id: id,
      category: map['category'] as String? ?? '',
      priority: priority,
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
  List<NotificationRule> _rules = [];

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];
    
    _rules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  void addReinforcementRule(NotificationRule rule) {
    final sanitized = CustomRuleValidator.clampAndSanitizeRule(rule);
    _rules.removeWhere((r) => r.id == sanitized.id);
    _rules.insert(0, sanitized);

    // Enforce custom rules count quota (max 50 per device)
    final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
    if (customRules.length > CustomRuleValidator.maxCustomRules) {
      final excessCount = customRules.length - CustomRuleValidator.maxCustomRules;
      final idsToRemove = customRules.sublist(customRules.length - excessCount).map((r) => r.id).toSet();
      _rules.removeWhere((r) => idsToRemove.contains(r.id));
    }

    _saveCustomRules();
  }

  /// Loads custom rules from local storage and prepends them.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content);
        if (decoded is List) {
          final customRules = CustomRuleValidator.validateAndSanitizeRules(decoded);
          _rules.removeWhere((r) => r.id.startsWith('rlhf-'));
          _rules.insertAll(0, customRules);
        } else {
          await file.writeAsString('[]');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules safely: $e');
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/rlhf_rules.json');
        await file.writeAsString('[]');
      } catch (_) {}
    }
  }

  /// Saves all custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      // Filter out base rules (assuming base rules don't have 'rlhf-' prefix in id)
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final list = customRules.map((r) => r.toMap()).toList();
      
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save custom RLHF rules: $e');
    }
  }

  /// Checks for exact word boundary match (\b...\b) of [keyword] in [text].
  bool _hasWordBoundaryMatch(String text, String keyword) {
    if (keyword.isEmpty) return false;
    final escaped = RegExp.escape(keyword.toLowerCase());
    final leadingBoundary = RegExp(r'^\w').hasMatch(keyword) ? r'\b' : '';
    final trailingBoundary = RegExp(r'\w$').hasMatch(keyword) ? r'\b' : '';
    final pattern = '$leadingBoundary$escaped$trailingBoundary';
    return RegExp(pattern, caseSensitive: false).hasMatch(text);
  }

  /// Scans the database to find the first rule matching this notification.
  /// Returns a [MatchedRuleResult] if a match is found, or null otherwise.
  MatchedRuleResult? match(AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    for (final rule in _rules) {
      // 1. Package match constraint
      final packageConditionMatches =
          rule.conditions.packages.isEmpty || rule.conditions.packages.contains(package);

      if (!packageConditionMatches) continue;

      // 2. Title keywords check
      bool titleMatch = false;
      String? matchedTitleWord;
      if (rule.conditions.titleKeywords.isNotEmpty) {
        for (final word in rule.conditions.titleKeywords) {
          if (_hasWordBoundaryMatch(titleLower, word)) {
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
          if (_hasWordBoundaryMatch(contentLower, word)) {
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
          isCustom: rule.id.startsWith('rlhf-'),
        );
      }
    }

    return null;
  }
}
