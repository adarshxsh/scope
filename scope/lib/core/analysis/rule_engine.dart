import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
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

  /// Compiles a signed rule asset envelope into compiled memory structures after verifying Ed25519 signature.
  void compile(String jsonStr) {
    Map<String, dynamic> envelope;
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        throw const RuleSecurityException(
            'Invalid envelope format: payload is not a signed JSON envelope map.');
      }
      envelope = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is RuleSecurityException) rethrow;
      throw RuleSecurityException('Failed to parse signed envelope JSON: $e');
    }

    final authorKeyId = envelope['author_key_id'] ?? envelope['author_id'];
    final signature = envelope['signature'] as String?;
    final rawPayload = envelope['payload'];

    if (authorKeyId == null || signature == null || signature.isEmpty || rawPayload == null) {
      throw const RuleSecurityException(
          'Envelope is missing required author key ID, signature, or payload.');
    }

    final String payloadStr = rawPayload is String ? rawPayload : json.encode(rawPayload);

    final isValid = RuleCrypto.verifyEd25519Signature(
      payloadStr: payloadStr,
      signatureHex: signature,
    );

    if (!isValid) {
      throw const RuleSecurityException(
          'Ed25519 cryptographic signature verification failed for rule asset payload.');
    }

    final Map<String, dynamic> parsedPayload = rawPayload is Map<String, dynamic>
        ? rawPayload
        : Map<String, dynamic>.from(json.decode(payloadStr) as Map);

    version = parsedPayload['version'] as String? ?? '0.0.0';
    final rawRules = parsedPayload['rules'] as List<dynamic>? ?? const [];

    _rules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  Future<void> addReinforcementRule(NotificationRule rule) async {
    _rules.insert(0, rule);
    await _saveCustomRules();
  }

  /// Loads custom rules from local storage and prepends them after HMAC-SHA256 verification.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content);
        if (decoded is! Map<String, dynamic> ||
            !decoded.containsKey('hmac') ||
            !decoded.containsKey('payload')) {
          throw const RuleSecurityException(
              'Invalid local RLHF rules format or missing HMAC integrity tag.');
        }

        final hmacHex = decoded['hmac'] as String? ?? '';
        final payload = decoded['payload'];
        final payloadStr = json.encode(payload);

        final deviceKey = RuleCrypto.deriveDeviceKey(dir.path);
        final isValid = RuleCrypto.verifyHMAC(
          payloadStr: payloadStr,
          expectedHmacHex: hmacHex,
          keyBytes: deviceKey,
        );

        if (!isValid) {
          throw const RuleSecurityException(
              'HMAC-SHA256 integrity verification failed for local custom RLHF rules.');
        }

        final list = payload as List<dynamic>? ?? const [];
        final customRules = list
            .map((r) => NotificationRule.fromMap(
                Map<String, dynamic>.from(r as Map)))
            .toList();
        // Insert custom rules at the top
        _rules.insertAll(0, customRules);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
      rethrow;
    }
  }

  /// Saves all custom RLHF rules to local storage with HMAC-SHA256 signature.
  Future<void> _saveCustomRules() async {
    try {
      // Filter out base rules (assuming base rules don't have 'rlhf-' prefix in id)
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final list = customRules.map((r) => r.toMap()).toList();
      final payloadStr = json.encode(list);

      final dir = await getApplicationDocumentsDirectory();
      final deviceKey = RuleCrypto.deriveDeviceKey(dir.path);
      final hmacHex = RuleCrypto.computeHMAC(
        payloadStr: payloadStr,
        keyBytes: deviceKey,
      );

      final envelope = {
        'hmac': hmacHex,
        'payload': list,
      };

      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(envelope));
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save custom RLHF rules: $e');
      rethrow;
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
