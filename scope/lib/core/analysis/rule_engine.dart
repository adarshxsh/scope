import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/models/notification_model.dart';

/// Condition definition for a notification classification rule.
class RuleCondition {
  final List<String> packages;
  final List<String> keywords;
  final List<String> titleKeywords;

  RuleCondition({
    List<String> packages = const [],
    List<String> keywords = const [],
    List<String> titleKeywords = const [],
  })  : packages = sanitizeList(packages),
        keywords = sanitizeList(keywords),
        titleKeywords = sanitizeList(titleKeywords);

  static List<String> sanitizeList(dynamic raw) {
    if (raw is! Iterable) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  factory RuleCondition.fromMap(Map<String, dynamic> map) {
    return RuleCondition(
      packages: sanitizeList(map['packages']),
      keywords: sanitizeList(map['keywords']),
      titleKeywords: sanitizeList(map['title_keywords']),
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

  NotificationRule({
    required String id,
    required String category,
    required String priority,
    required this.conditions,
  })  : id = id.trim().isNotEmpty
            ? id.trim()
            : 'rlhf-${DateTime.now().millisecondsSinceEpoch}',
        category =
            category.trim().isNotEmpty ? category.trim() : 'uncategorized',
        priority = priority.trim().isNotEmpty ? priority.trim() : 'low';

  factory NotificationRule.fromMap(Map<String, dynamic> map) {
    final rawId = map['id']?.toString().trim() ?? '';
    final sanitizedId = rawId.isNotEmpty
        ? rawId
        : 'rlhf-${DateTime.now().millisecondsSinceEpoch}';

    return NotificationRule(
      id: sanitizedId,
      category: map['category']?.toString().trim() ?? 'uncategorized',
      priority: map['priority']?.toString().trim() ?? 'low',
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
  /// Maximum allowed custom RLHF rules in memory and on disk to bound memory consumption.
  static const int maxCustomRules = 100;

  String version = '0.0.0';
  List<NotificationRule> _rules = [];

  /// Getters for inspection and diagnostic telemetry
  List<NotificationRule> get rules => List.unmodifiable(_rules);
  int get ruleCount => _rules.length;
  int get customRuleCount =>
      _rules.where((r) => r.id.startsWith('rlhf-')).length;

  /// Returns structured diagnostic information without exposing cleartext PII.
  Map<String, dynamic> getDiagnostics() {
    final seen = <String>{};
    bool duplicateFound = false;
    for (final r in _rules) {
      if (!seen.add(r.id)) {
        duplicateFound = true;
        break;
      }
    }

    return {
      'version': version,
      'totalRules': _rules.length,
      'customRules': customRuleCount,
      'baseRules': _rules.length - customRuleCount,
      'hasDuplicates': duplicateFound,
    };
  }

  /// Helper to deduplicate a rule list preserving order (first occurrence wins).
  List<NotificationRule> _deduplicateRules(List<NotificationRule> rules) {
    final seenIds = <String>{};
    final unique = <NotificationRule>[];
    for (final r in rules) {
      if (seenIds.add(r.id)) {
        unique.add(r);
      }
    }
    return unique;
  }

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      version = parsed['version'] as String? ?? '0.0.0';
      final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

      final compiledBaseRules = rawRules
          .map((r) =>
              NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();

      _rules = _deduplicateRules(compiledBaseRules);
    } catch (e) {
      debugPrint('RuleEngine: Error compiling base rules: $e');
    }
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  void addReinforcementRule(NotificationRule rule) {
    final sanitizedId = rule.id.trim().isNotEmpty
        ? rule.id.trim()
        : 'rlhf-${DateTime.now().millisecondsSinceEpoch}';

    final sanitizedRule = NotificationRule(
      id: sanitizedId,
      category: rule.category.trim(),
      priority: rule.priority.trim(),
      conditions: rule.conditions,
    );

    // Remove any existing rule with identical identifier to prevent duplicate object accumulation
    _rules.removeWhere((r) => r.id == sanitizedRule.id);

    // Prepend rule to top of chain
    _rules.insert(0, sanitizedRule);

    // Enforce maximum custom rule count threshold
    _enforceCustomRuleBounds();

    _saveCustomRules();
  }

  /// Loads custom rules from local storage and prepends them.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content);

        if (list is! List) {
          debugPrint('RuleEngine: Malformed custom rules file, skipping.');
          return;
        }

        final loadedRules = list
            .map((r) => NotificationRule.fromMap(
                Map<String, dynamic>.from(r as Map)))
            .toList();

        // Deduplicate loaded rules among themselves
        final uniqueLoadedRules = _deduplicateRules(loadedRules);

        // Remove existing custom rules from _rules to avoid accumulating duplicates on reload
        final loadedIds = uniqueLoadedRules.map((r) => r.id).toSet();
        _rules.removeWhere((r) => loadedIds.contains(r.id) || r.id.startsWith('rlhf-'));

        // Insert custom rules at the top
        _rules.insertAll(0, uniqueLoadedRules);

        // Enforce maximum custom rule bounds
        _enforceCustomRuleBounds();

        debugPrint(
            'RuleEngine: Loaded ${uniqueLoadedRules.length} custom RLHF rules without duplicates.');
      }
    } catch (e) {
      debugPrint('RuleEngine: Failed to load custom RLHF rules: $e');
    }
  }

  /// Bounds custom RLHF rules to [maxCustomRules] items.
  void _enforceCustomRuleBounds() {
    final customRules =
        _rules.where((r) => r.id.startsWith('rlhf-')).toList();

    if (customRules.length > maxCustomRules) {
      final customToKeep = customRules.take(maxCustomRules).toSet();
      _rules.removeWhere(
          (r) => r.id.startsWith('rlhf-') && !customToKeep.contains(r));
    }
  }

  /// Saves all custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      // Filter out base rules, keeping only custom RLHF rules
      final customRules =
          _rules.where((r) => r.id.startsWith('rlhf-')).toList();

      final uniqueCustom = _deduplicateRules(customRules)
          .take(maxCustomRules)
          .toList();

      final list = uniqueCustom.map((r) => r.toMap()).toList();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));

      debugPrint(
          'RuleEngine: Saved ${uniqueCustom.length} custom RLHF rules to storage.');
    } catch (e) {
      debugPrint('RuleEngine: Failed to save custom RLHF rules: $e');
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
