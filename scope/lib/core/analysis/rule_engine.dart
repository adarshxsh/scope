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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationRule &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
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
  List<NotificationRule> _rules = [];

  /// Unmodifiable view of currently loaded rules.
  List<NotificationRule> get rules => List.unmodifiable(_rules);

  /// Unmodifiable view of custom RLHF rules.
  List<NotificationRule> get customRules =>
      List.unmodifiable(_rules.where((r) => r.id.startsWith('rlhf-')));

  /// Count of custom RLHF rules in memory.
  int get customRuleCount =>
      _rules.where((r) => r.id.startsWith('rlhf-')).length;

  /// Total count of all loaded rules (base + custom).
  int get totalRuleCount => _rules.length;

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      version = parsed['version'] as String? ?? '0.0.0';
      final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

      final seenIds = <String>{};
      final baseRules = <NotificationRule>[];

      for (final r in rawRules) {
        if (r is Map) {
          final rule = NotificationRule.fromMap(Map<String, dynamic>.from(r));
          if (rule.id.isNotEmpty && seenIds.add(rule.id)) {
            baseRules.add(rule);
          }
        }
      }

      _rules = baseRules;
    } catch (e) {
      // ignore: avoid_print
      print('Failed to compile rules JSON: $e');
    }
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  /// Deduplicates against existing rule identifiers to prevent duplicate accumulation in memory and storage.
  Future<void> addReinforcementRule(NotificationRule rule) async {
    if (rule.id.trim().isEmpty) {
      return;
    }

    // Remove any existing rule with the same ID (whether base or custom)
    _rules.removeWhere((r) => r.id == rule.id);

    // Prepend rule to the top of evaluation chain
    _rules.insert(0, rule);

    // Persist custom rules to storage
    await _saveCustomRules();
  }

  /// Removes a custom RLHF rule by identifier and updates local storage.
  Future<void> removeReinforcementRule(String ruleId) async {
    if (ruleId.trim().isEmpty) return;
    _rules.removeWhere((r) => r.id == ruleId);
    await _saveCustomRules();
  }

  /// Clears all custom RLHF rules and updates local storage.
  Future<void> clearCustomRules() async {
    _rules.removeWhere((r) => r.id.startsWith('rlhf-'));
    await _saveCustomRules();
  }

  /// Loads custom rules from local storage, deduplicates them, and prepends them.
  /// Corrupt or malformed JSON storage is handled by overwriting with empty array.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (!await file.exists()) {
        return;
      }

      final content = await file.readAsString();
      dynamic decoded;
      try {
        decoded = json.decode(content);
      } catch (parseError) {
        // Corrupt or malformed JSON array; recover by overwriting file with empty array
        // ignore: avoid_print
        print('Corrupt RLHF rules JSON detected ($parseError); resetting storage.');
        await file.writeAsString('[]');
        return;
      }

      if (decoded is! List) {
        // ignore: avoid_print
        print('RLHF rules JSON is not a list; resetting storage.');
        await file.writeAsString('[]');
        return;
      }

      final seenIds = <String>{};
      final customRules = <NotificationRule>[];

      for (final item in decoded) {
        if (item is Map) {
          final rule = NotificationRule.fromMap(Map<String, dynamic>.from(item));
          if (rule.id.isNotEmpty && seenIds.add(rule.id)) {
            customRules.add(rule);
          }
        }
      }

      // Remove any existing custom rules (or rules with matching IDs) from memory before prepending
      final customIds = customRules.map((r) => r.id).toSet();
      _rules.removeWhere((r) => customIds.contains(r.id) || r.id.startsWith('rlhf-'));

      // Prepend deduplicated custom rules at the top
      _rules.insertAll(0, customRules);
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to local storage without duplicates.
  Future<void> _saveCustomRules() async {
    try {
      final seenIds = <String>{};
      final customRules = <NotificationRule>[];

      for (final r in _rules) {
        if (r.id.startsWith('rlhf-') && seenIds.add(r.id)) {
          customRules.add(r);
        }
      }

      final list = customRules.map((r) => r.toMap()).toList();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save custom RLHF rules: $e');
    }
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
        );
      }
    }

    return null;
  }
}
