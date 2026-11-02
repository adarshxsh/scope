import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/crypto_utils.dart';
import 'package:scope/core/models/notification_model.dart';

export 'package:scope/core/analysis/crypto_utils.dart' show IntegrityException;

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

  /// Compiles a signed JSON rules envelope into compiled memory structures.
  ///
  /// Validates Ed25519 signature before compiling rules.
  /// Throws [IntegrityException] if envelope is missing required fields, unsigned,
  /// or signature verification fails.
  void compile(String jsonStr) {
    Map<String, dynamic> parsed;
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        throw const IntegrityException('Rule payload must be a JSON envelope map');
      }
      parsed = decoded;
    } catch (e) {
      if (e is IntegrityException) rethrow;
      throw IntegrityException('Failed to parse JSON rule envelope: $e');
    }

    if (!parsed.containsKey('payload') ||
        !parsed.containsKey('signature') ||
        !parsed.containsKey('key_id')) {
      throw const IntegrityException(
        'Rule envelope missing required fields: must contain "payload", "signature", and "key_id"',
      );
    }

    final signature = parsed['signature'] as String? ?? '';
    final keyId = parsed['key_id'] as String? ?? '';
    final rawPayload = parsed['payload'];

    if (signature.isEmpty || keyId.isEmpty || rawPayload == null) {
      throw const IntegrityException(
        'Rule envelope fields cannot be empty: "payload", "signature", or "key_id"',
      );
    }

    List<int> payloadBytes;
    if (rawPayload is String) {
      payloadBytes = utf8.encode(rawPayload);
    } else {
      payloadBytes = utf8.encode(json.encode(rawPayload));
    }

    final isValid = CryptoUtils.verifyEd25519Signature(
      messageBytes: payloadBytes,
      signatureBase64: signature,
      keyId: keyId,
    );

    if (!isValid) {
      throw const IntegrityException(
        'Ed25519 signature verification failed: rule payload has been tampered with or corrupted',
      );
    }

    Map<String, dynamic> payloadMap;
    if (rawPayload is Map<String, dynamic>) {
      payloadMap = rawPayload;
    } else if (rawPayload is Map) {
      payloadMap = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String) {
      final decoded = json.decode(rawPayload);
      if (decoded is! Map) {
        throw const IntegrityException('String payload is not a valid JSON object');
      }
      payloadMap = Map<String, dynamic>.from(decoded);
    } else {
      throw const IntegrityException('Invalid rule payload format');
    }

    version = payloadMap['version'] as String? ?? '0.0.0';
    final rawRules = payloadMap['rules'] as List<dynamic>? ?? const [];

    _rules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Compiles hardcoded safe default rules when signature verification fails.
  void compileFallbackRules() {
    version = 'fallback-1.0.0';
    _rules = const [
      NotificationRule(
        id: 'otp_security',
        category: 'sys',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['otp', 'verification code', 'one-time password', 'security code'],
        ),
      ),
      NotificationRule(
        id: 'finance_debit',
        category: 'finance',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['debited', 'withdrawn', 'spent', 'deducted', 'charge'],
          titleKeywords: ['alert', 'bank', 'card'],
        ),
      ),
      NotificationRule(
        id: 'scholarship_portal',
        category: 'scholarship',
        priority: 'critical',
        conditions: RuleCondition(
          packages: ['in.gov.scholarships'],
          keywords: ['deadline alert', 'apply before', 'closes in'],
        ),
      ),
    ];
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  void addReinforcementRule(NotificationRule rule) {
    _rules.insert(0, rule);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage and prepends them after HMAC signature verification.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content);

        if (decoded is! Map<String, dynamic>) {
          // ignore: avoid_print
          print('AUDIT: rlhf_rules.json is not a valid envelope - discarding custom rules');
          return;
        }

        final rulesListRaw = decoded['rules'] ?? decoded['payload'];
        final hmacStr = decoded['hmac'] as String? ?? '';

        if (rulesListRaw == null || hmacStr.isEmpty) {
          // ignore: avoid_print
          print('AUDIT: rlhf_rules.json missing rules payload or HMAC signature - discarding custom rules');
          return;
        }

        final bytesToVerify = utf8.encode(json.encode(rulesListRaw));
        final isHmacValid = CryptoUtils.verifyHmacSha256(bytesToVerify, hmacStr);

        if (!isHmacValid) {
          // ignore: avoid_print
          print('AUDIT: Local custom rules HMAC verification failed - file tampered! Discarding rules.');
          return;
        }

        final list = rulesListRaw as List<dynamic>;
        final customRules = list
            .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();

        // Insert custom rules at the top
        _rules.insertAll(0, customRules);
      }
    } catch (e) {
      // ignore: avoid_print
      print('AUDIT: Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to local storage with an HMAC-SHA256 signature.
  Future<void> _saveCustomRules() async {
    try {
      // Filter out base rules (assuming base rules don't have 'rlhf-' prefix in id)
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final list = customRules.map((r) => r.toMap()).toList();

      final listBytes = utf8.encode(json.encode(list));
      final hmacStr = CryptoUtils.generateHmacSha256(listBytes);

      final envelope = {
        'rules': list,
        'hmac': hmacStr,
      };

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(envelope));
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
