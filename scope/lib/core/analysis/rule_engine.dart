import 'dart:convert';
import 'dart:io';
import 'package:scope/core/analysis/rule_crypto.dart';
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

  /// Compiles a raw JSON rules envelope after verifying its Ed25519 author signature.
  /// Safely rejects unverified or corrupt rules and reverts to safe defaults without crashing.
  Future<bool> compile(String jsonStr) async {
    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      final payload = await RuleCrypto.verifyBaseRulesEnvelope(parsed);
      if (payload == null) {
        // ignore: avoid_print
        print('RuleEngine: Base rules signature verification failed! Triggering safe fallback.');
        _rules = [];
        version = '0.0.0';
        return false;
      }

      version = payload['version'] as String? ?? '0.0.0';
      final rawRules = payload['rules'] as List<dynamic>? ?? const [];

      _rules = rawRules
          .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('RuleEngine: Exception during rule compilation: $e');
      _rules = [];
      version = '0.0.0';
      return false;
    }
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  Future<bool> addReinforcementRule(NotificationRule rule) async {
    _rules.insert(0, rule);
    return await _saveCustomRules();
  }

  /// Loads custom rules from local storage after verifying device-bound HMAC signature.
  /// Safely rejects tampered rule files and falls back to base rules without crashing.
  Future<bool> loadCustomRules() async {
    try {
      final dir = await RuleCrypto.getStorageDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = json.decode(content) as Map<String, dynamic>;
        final verifiedRulesList = await RuleCrypto.verifyCustomRulesEnvelope(map);

        if (verifiedRulesList == null) {
          // ignore: avoid_print
          print('RuleEngine: Dynamic user rules failed HMAC verification! Reverting safely to base rules.');
          return false;
        }

        final customRules = verifiedRulesList
            .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();
        // Insert custom rules at the top
        _rules.insertAll(0, customRules);
        return true;
      }
    } catch (e) {
      // ignore: avoid_print
      print('RuleEngine: Failed to load custom RLHF rules: $e');
    }
    return false;
  }

  /// Saves all custom RLHF rules to local storage with device-bound HMAC-SHA256 signature header.
  Future<bool> _saveCustomRules() async {
    try {
      // Filter out base rules (assuming base rules don't have 'rlhf-' prefix in id)
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final list = customRules.map((r) => r.toMap()).toList();

      final envelope = await RuleCrypto.createSignedCustomRulesEnvelope(list);

      final dir = await RuleCrypto.getStorageDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(envelope));
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('RuleEngine: Failed to save custom RLHF rules: $e');
      return false;
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
