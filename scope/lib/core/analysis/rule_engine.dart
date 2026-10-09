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
    List<String> parseList(dynamic raw) {
      if (raw is Iterable) {
        return raw.where((e) => e != null).map((e) => e.toString()).toList();
      }
      return const [];
    }

    return RuleCondition(
      packages: parseList(map['packages']),
      keywords: parseList(map['keywords']),
      titleKeywords: parseList(map['title_keywords']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packages': packages,
      'keywords': keywords,
      'title_keywords': titleKeywords,
    };
  }

  /// Checks structural condition bounds: max 10 items per array and max 100 characters per string.
  bool get isValid {
    if (packages.length > 10 || keywords.length > 10 || titleKeywords.length > 10) {
      return false;
    }
    for (final p in packages) {
      if (p.length > 100) return false;
    }
    for (final k in keywords) {
      if (k.length > 100) return false;
    }
    for (final tk in titleKeywords) {
      if (tk.length > 100) return false;
    }
    return true;
  }
}

/// A parsed match rule from JSON.
class NotificationRule {
  final String id;
  final String category;
  final String priority;
  final RuleCondition conditions;

  static const Set<String> validPriorities = {'critical', 'high', 'medium', 'low'};
  static const Set<String> validCategories = {
    'sys', 'system', 'finance', 'financial', 'scholarship',
    'msg', 'message', 'work', 'health', 'promo', 'promotional',
    'social', 'personal', 'email', 'other', 'cloud storage',
    'onboarding', 'system_status',
  };

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
        map['conditions'] is Map
            ? Map<String, dynamic>.from(map['conditions'] as Map)
            : const {},
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

  /// Validates schema bounds including priority, category, ID, and condition limits.
  bool get isValid {
    if (id.trim().isEmpty) return false;
    if (!validPriorities.contains(priority.trim().toLowerCase())) return false;
    if (!validCategories.contains(category.trim().toLowerCase())) return false;
    if (!conditions.isValid) return false;
    return true;
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
  List<NotificationRule> _rules = [];

  static const int maxCustomRules = 50;

  /// Exposes unmodifiable list of rules for inspection/testing.
  List<NotificationRule> get rules => List.unmodifiable(_rules);

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];
    
    _rules = rawRules
        .whereType<Map>()
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  /// Rejects invalid rules or when custom rule capacity limit (50) is reached.
  bool addReinforcementRule(NotificationRule rule) {
    if (!rule.isValid) {
      return false;
    }
    final customRulesCount = _rules.where((r) => r.id.startsWith('rlhf-')).length;
    if (customRulesCount >= maxCustomRules) {
      return false;
    }

    _rules.insert(0, rule);
    _saveCustomRules();
    return true;
  }

  /// Loads custom rules from local storage and prepends them.
  /// Drops entries violating schema bounds and quarantines corrupted files/entries.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      final quarantineFile = File('${dir.path}/rlhf_rules.quarantine.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        List<NotificationRule> validCustomRules = [];
        bool needsQuarantine = false;

        try {
          final decoded = json.decode(content);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                try {
                  final rule = NotificationRule.fromMap(Map<String, dynamic>.from(item));
                  if (rule.isValid) {
                    if (validCustomRules.length < maxCustomRules) {
                      validCustomRules.add(rule);
                    } else {
                      needsQuarantine = true;
                    }
                  } else {
                    needsQuarantine = true;
                  }
                } catch (_) {
                  needsQuarantine = true;
                }
              } else {
                needsQuarantine = true;
              }
            }
          } else {
            needsQuarantine = true;
          }
        } catch (e) {
          needsQuarantine = true;
        }

        if (needsQuarantine) {
          try {
            await quarantineFile.writeAsString(content);
          } catch (_) {}
        }

        // Replace pre-existing custom rules in _rules with valid ones
        _rules.removeWhere((r) => r.id.startsWith('rlhf-'));
        _rules.insertAll(0, validCustomRules);

        // Save sanitized rule list back
        await _saveCustomRules();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).take(maxCustomRules).toList();
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
  /// Traps runtime exceptions during condition evaluation to isolate failures.
  MatchedRuleResult? match(AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    for (final rule in _rules) {
      try {
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
      } catch (e) {
        // Log warning and safely continue matching remaining rules
        // ignore: avoid_print
        print('Error evaluating rule ${rule.id}: $e');
      }
    }

    return null;
  }
}
