import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/models/notification_model.dart';

/// Evaluation tiers for notification classification rules.
enum RuleTier {
  system,
  custom,
}

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
      titleKeywords: List<String>.from(map['title_keywords'] ?? map['titleKeywords'] as Iterable? ?? const []),
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
  final RuleTier tier;

  const NotificationRule({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditions,
    this.tier = RuleTier.custom,
  });

  factory NotificationRule.fromMap(
    Map<String, dynamic> map, {
    RuleTier defaultTier = RuleTier.custom,
  }) {
    final tierStr = map['tier'] as String?;
    RuleTier tier = defaultTier;
    if (tierStr == 'system') {
      tier = RuleTier.system;
    } else if (tierStr == 'custom') {
      tier = RuleTier.custom;
    }

    return NotificationRule(
      id: map['id'] as String? ?? '',
      category: map['category'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      conditions: RuleCondition.fromMap(
        Map<String, dynamic>.from(map['conditions'] as Map? ?? const {}),
      ),
      tier: tier,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'priority': priority,
      'conditions': conditions.toMap(),
      'tier': tier.name,
    };
  }
}

/// Result of schema validation on a custom rule.
class RuleValidationResult {
  final bool isValid;
  final String? error;

  const RuleValidationResult._(this.isValid, this.error);

  factory RuleValidationResult.success() => const RuleValidationResult._(true, null);
  factory RuleValidationResult.failure(String error) => RuleValidationResult._(false, error);
}

/// Structural schema validator for user-defined custom rules.
class RuleSchemaValidator {
  static const Set<String> reservedSystemRuleIds = {
    'otp_security',
    'finance_debit',
    'scholarship_portal',
    'family_urgent',
    'work_collaboration',
    'medical_reminder',
    'promo_deals',
    'social_engagement',
  };

  static const Set<String> validCustomPriorities = {
    'high',
    'medium',
    'low',
  };

  static const String customIdPrefix = 'rlhf-';

  /// Validates a custom user-defined rule Map against the strict structural schema.
  static RuleValidationResult validateCustomRuleMap(
    Map<String, dynamic> map, {
    Set<String>? existingIds,
  }) {
    // 1. Validate ID
    final idObj = map['id'];
    if (idObj == null || idObj is! String || idObj.trim().isEmpty) {
      return RuleValidationResult.failure('Custom rule ID must be a non-empty string.');
    }
    final id = idObj.trim();
    if (!id.startsWith(customIdPrefix)) {
      return RuleValidationResult.failure('Custom rule ID "$id" must start with "$customIdPrefix".');
    }
    final cleanId = id.substring(customIdPrefix.length);
    if (reservedSystemRuleIds.contains(id) || reservedSystemRuleIds.contains(cleanId)) {
      return RuleValidationResult.failure('Custom rule ID "$id" attempts to override reserved system rule ID.');
    }
    if (existingIds != null && existingIds.contains(id)) {
      return RuleValidationResult.failure('Custom rule ID "$id" is a duplicate ID.');
    }

    // 2. Validate Category
    final categoryObj = map['category'];
    if (categoryObj == null || categoryObj is! String || categoryObj.trim().isEmpty) {
      return RuleValidationResult.failure('Custom rule category must be a non-empty string.');
    }

    // 3. Validate Priority
    final priorityObj = map['priority'];
    if (priorityObj == null || priorityObj is! String || priorityObj.trim().isEmpty) {
      return RuleValidationResult.failure('Custom rule priority must be a non-empty string.');
    }
    final priority = priorityObj.trim().toLowerCase();
    if (priority == 'critical') {
      return RuleValidationResult.failure('Custom rules cannot claim critical priority.');
    }
    if (!validCustomPriorities.contains(priority)) {
      return RuleValidationResult.failure('Custom rule priority "$priority" is invalid. Allowed: ${validCustomPriorities.join(', ')}.');
    }

    // 4. Validate Conditions
    final conditionsObj = map['conditions'];
    if (conditionsObj == null || conditionsObj is! Map) {
      return RuleValidationResult.failure('Custom rule conditions must be a non-empty object.');
    }
    final condMap = Map<String, dynamic>.from(conditionsObj);

    final packagesRaw = condMap['packages'];
    final keywordsRaw = condMap['keywords'];
    final titleKeywordsRaw = condMap['title_keywords'] ?? condMap['titleKeywords'];

    final packages = _extractStringList(packagesRaw);
    final keywords = _extractStringList(keywordsRaw);
    final titleKeywords = _extractStringList(titleKeywordsRaw);

    if (packages == null || keywords == null || titleKeywords == null) {
      return RuleValidationResult.failure('Custom rule condition elements must be string lists.');
    }

    // Check for empty condition set wildcard (all lists empty)
    if (packages.isEmpty && keywords.isEmpty && titleKeywords.isEmpty) {
      return RuleValidationResult.failure('Custom rule conditions cannot be empty (empty condition wildcard).');
    }

    // Check for empty keyword string wildcards
    if (packages.any((p) => p.trim().isEmpty)) {
      return RuleValidationResult.failure('Custom rule package list contains empty keyword string wildcard.');
    }
    if (keywords.any((k) => k.trim().isEmpty)) {
      return RuleValidationResult.failure('Custom rule keywords list contains empty keyword string wildcard.');
    }
    if (titleKeywords.any((tk) => tk.trim().isEmpty)) {
      return RuleValidationResult.failure('Custom rule title keywords list contains empty keyword string wildcard.');
    }

    return RuleValidationResult.success();
  }

  /// Validates a [NotificationRule] instance.
  static RuleValidationResult validateCustomRule(
    NotificationRule rule, {
    Set<String>? existingIds,
  }) {
    return validateCustomRuleMap(rule.toMap(), existingIds: existingIds);
  }

  static List<String>? _extractStringList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! Iterable) return null;
    final list = <String>[];
    for (final item in raw) {
      if (item is! String) return null;
      list.add(item);
    }
    return list;
  }
}

/// The result returned by a successful rule engine match.
class MatchedRuleResult {
  final String ruleId;
  final String category;
  final String priority;
  final String matchedSignal;
  final RuleTier tier;

  const MatchedRuleResult({
    required this.ruleId,
    required this.category,
    required this.priority,
    required this.matchedSignal,
    this.tier = RuleTier.system,
  });

  @override
  String toString() => 'MatchedRuleResult(ruleId: $ruleId, category: $category, '
      'priority: $priority, matchedSignal: $matchedSignal, tier: ${tier.name})';
}

/// Compiled rule engine matching raw notifications against in-memory patterns.
class RuleEngine {
  String version = '0.0.0';
  List<NotificationRule> _systemRules = [];
  List<NotificationRule> _customRules = [];
  Directory? customRulesDir;

  RuleEngine({this.customRulesDir});

  List<NotificationRule> get systemRules => List.unmodifiable(_systemRules);
  List<NotificationRule> get customRules => List.unmodifiable(_customRules);
  List<NotificationRule> get rules => List.unmodifiable([..._systemRules, ..._customRules]);

  Future<Directory?> _getStorageDir() async {
    if (customRulesDir != null) return customRulesDir;
    try {
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      // ignore: avoid_print
      print('Failed to get application documents directory: $e');
      return null;
    }
  }

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

    _systemRules = rawRules
        .map((r) => NotificationRule.fromMap(
              Map<String, dynamic>.from(r as Map),
              defaultTier: RuleTier.system,
            ))
        .toList();
  }

  /// Adds a user-defined reinforcement learning rule after strict schema validation.
  /// Returns true if added successfully, false if validation failed.
  bool addReinforcementRule(NotificationRule rule) {
    final existingIds = {
      ..._systemRules.map((r) => r.id),
      ..._customRules.map((r) => r.id),
    };
    final validation = RuleSchemaValidator.validateCustomRule(
      rule,
      existingIds: existingIds,
    );

    if (!validation.isValid) {
      // ignore: avoid_print
      print('Schema validation failed for reinforcement rule: ${validation.error}');
      return false;
    }

    final customRule = NotificationRule(
      id: rule.id,
      category: rule.category,
      priority: rule.priority,
      conditions: rule.conditions,
      tier: RuleTier.custom,
    );

    _customRules.insert(0, customRule);
    _saveCustomRules().catchError((e) {
      // ignore: avoid_print
      print('Failed to save custom RLHF rules: $e');
    });
    return true;
  }

  /// Loads custom rules from local storage, validating each against the structural schema.
  Future<void> loadCustomRules() async {
    try {
      final dir = await _getStorageDir();
      if (dir == null) return;
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content) as List<dynamic>;
        final validCustomRules = <NotificationRule>[];
        final existingIds = {..._systemRules.map((r) => r.id)};

        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final validation = RuleSchemaValidator.validateCustomRuleMap(
              map,
              existingIds: existingIds,
            );

            if (validation.isValid) {
              final rule = NotificationRule.fromMap(map, defaultTier: RuleTier.custom);
              validCustomRules.add(rule);
              existingIds.add(rule.id);
            } else {
              // ignore: avoid_print
              print('Schema validation error loading custom rule: ${validation.error}. Safely discarding invalid rule.');
            }
          } else {
            // ignore: avoid_print
            print('Schema validation error loading custom rule: Item is not a valid JSON map. Safely discarding.');
          }
        }
        _customRules = validCustomRules;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all valid custom RLHF rules to local storage.
  Future<void> _saveCustomRules() async {
    try {
      final dir = await _getStorageDir();
      if (dir == null) return;
      final list = _customRules.map((r) => r.toMap()).toList();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(list));
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save custom RLHF rules: $e');
    }
  }

  /// Scans the database to find the first rule matching this notification.
  /// Evaluates System Critical Tier rules first, then Custom User Tier rules.
  /// Returns a [MatchedRuleResult] if a match is found, or null otherwise.
  MatchedRuleResult? match(AppNotification notification) {
    // Tier 1: System Rules
    final systemMatch = _evaluateRuleList(_systemRules, notification);
    if (systemMatch != null) return systemMatch;

    // Tier 2: Custom User Rules
    final customMatch = _evaluateRuleList(_customRules, notification);
    if (customMatch != null) return customMatch;

    return null;
  }

  MatchedRuleResult? _evaluateRuleList(List<NotificationRule> ruleList, AppNotification notification) {
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
          tier: rule.tier,
        );
      }
    }

    return null;
  }
}
