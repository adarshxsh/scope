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
  List<NotificationRule> _baseRules = [];
  List<NotificationRule> _customRules = [];

  List<NotificationRule> get baseRules => List.unmodifiable(_baseRules);
  List<NotificationRule> get customRules => List.unmodifiable(_customRules);
  List<NotificationRule> get rules => List.unmodifiable([..._baseRules, ..._customRules]);

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _baseRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Validates and prepends a user-defined reinforcement learning rule to the custom rules tier.
  bool addReinforcementRule(NotificationRule rule) {
    final sanitized = CustomRuleValidator.validate(rule);
    if (sanitized == null) {
      return false;
    }

    if (_customRules.length >= CustomRuleValidator.maxCustomRules) {
      return false;
    }

    _customRules.insert(0, sanitized);
    _saveCustomRules();
    return true;
  }

  /// Loads custom rules from local storage into the custom rules tier.
  Future<void> loadCustomRules() async {
    _customRules.clear();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        dynamic list;
        try {
          list = json.decode(content);
        } catch (e) {
          // ignore: avoid_print
          print('Corrupted rlhf_rules.json detected: $e');
          await _saveCustomRules();
          return;
        }

        if (list is List) {
          final loaded = <NotificationRule>[];
          bool needSanitizedRewrite = false;

          for (final item in list) {
            if (item is Map) {
              try {
                final rule = NotificationRule.fromMap(Map<String, dynamic>.from(item));
                final sanitized = CustomRuleValidator.validate(rule);
                if (sanitized != null) {
                  loaded.add(sanitized);
                } else {
                  needSanitizedRewrite = true;
                }
              } catch (_) {
                needSanitizedRewrite = true;
              }
            } else {
              needSanitizedRewrite = true;
            }
          }

          if (loaded.length > CustomRuleValidator.maxCustomRules) {
            needSanitizedRewrite = true;
            _customRules = loaded.take(CustomRuleValidator.maxCustomRules).toList();
          } else {
            _customRules = loaded;
          }

          if (needSanitizedRewrite) {
            await _saveCustomRules();
          }
        } else {
          await _saveCustomRules();
        }
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

  /// Scans the database to find the first matching rule.
  /// Evaluates base system rules prior to custom RLHF rules.
  MatchedRuleResult? match(AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    // 1. Base rules tier evaluation
    final baseMatch = _matchRuleList(_baseRules, contentLower, titleLower, package, isCustom: false);
    if (baseMatch != null) {
      return baseMatch;
    }

    // 2. Custom rules tier evaluation
    return _matchRuleList(_customRules, contentLower, titleLower, package, isCustom: true);
  }

  MatchedRuleResult? _matchRuleList(
    List<NotificationRule> ruleList,
    String contentLower,
    String titleLower,
    String package, {
    required bool isCustom,
  }) {
    for (final rule in ruleList) {
      final packageConditionMatches =
          rule.conditions.packages.isEmpty ||
          rule.conditions.packages.any((p) => p.toLowerCase() == package);

      if (!packageConditionMatches) continue;

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
          isCustom: isCustom,
        );
      }
    }
    return null;
  }
}
