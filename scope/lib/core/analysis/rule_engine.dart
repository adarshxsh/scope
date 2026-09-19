import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/models/notification_model.dart';

/// Exception thrown when rule envelope integrity or HMAC signature verification fails.
class IntegrityException implements Exception {
  final String message;
  const IntegrityException(this.message);

  @override
  String toString() => 'IntegrityException: $message';
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

  /// Static default fallback rules loaded when rule compilation or verification fails.
  static final List<NotificationRule> _defaultFallbackRules = [
    const NotificationRule(
      id: 'otp_security',
      category: 'sys',
      priority: 'critical',
      conditions: RuleCondition(
        keywords: ['otp', 'verification code', 'one-time password', 'security code'],
      ),
    ),
    const NotificationRule(
      id: 'finance_debit',
      category: 'finance',
      priority: 'critical',
      conditions: RuleCondition(
        keywords: ['debited', 'withdrawn', 'spent', 'deducted', 'sent rs', 'sent inr', 'charge'],
        titleKeywords: ['alert', 'bank', 'charge', 'card'],
      ),
    ),
  ];

  /// Obfuscated signing key used for on-device HMAC verification and signing.
  static String get _defaultSigningKey {
    final keyBytes = [
      115, 99, 111, 112, 101, 95, 114, 117, 108, 101, 115, 95, 115, 101, 99, 114,
      101, 116, 95, 115, 97, 108, 116, 95, 107, 101, 121, 95, 50, 48, 50, 54
    ];
    return utf8.decode(keyBytes);
  }

  /// Generates a signed envelope Map wrapping payload with SHA-256 digest and HMAC-SHA256 signature.
  static Map<String, dynamic> createSignedEnvelope(
    dynamic payload, {
    String version = '1.0.0',
    String? signingKey,
  }) {
    final key = signingKey ?? _defaultSigningKey;
    final payloadJson = json.encode(payload);
    final digest = sha256.convert(utf8.encode(payloadJson)).toString();
    final hmac = Hmac(sha256, utf8.encode(key));
    final signature = hmac.convert(utf8.encode(digest)).toString();

    return {
      'version': version,
      'digest': digest,
      'signature': signature,
      'payload': payload,
    };
  }

  /// Verifies the SHA-256 payload digest and HMAC-SHA256 signature of a parsed envelope.
  /// Throws [IntegrityException] if verification fails or required fields are missing.
  static void verifyEnvelope(Map<String, dynamic> parsed, {String? signingKey}) {
    final key = signingKey ?? _defaultSigningKey;

    final digest = parsed['digest'] as String? ??
        parsed['payload_digest'] as String? ??
        parsed['sha256'] as String?;
    final signature = parsed['signature'] as String? ??
        parsed['hmac'] as String? ??
        parsed['hmac_signature'] as String?;

    if (digest == null || signature == null) {
      throw const IntegrityException('Missing envelope integrity metadata (digest or signature)');
    }

    final payload = parsed['payload'] ?? parsed['rules'];
    if (payload == null) {
      throw const IntegrityException('Missing envelope payload data');
    }

    final payloadJson = json.encode(payload);
    final computedDigest = sha256.convert(utf8.encode(payloadJson)).toString();

    if (computedDigest.toLowerCase() != digest.toLowerCase()) {
      throw IntegrityException(
        'Corrupted payload digest: calculated $computedDigest but found $digest',
      );
    }

    final hmac = Hmac(sha256, utf8.encode(key));
    final computedSignatureFromDigest = hmac.convert(utf8.encode(computedDigest)).toString();
    final computedSignatureFromPayload = hmac.convert(utf8.encode(payloadJson)).toString();

    final sigLower = signature.toLowerCase();
    if (sigLower != computedSignatureFromDigest.toLowerCase() &&
        sigLower != computedSignatureFromPayload.toLowerCase()) {
      throw IntegrityException(
        'Invalid HMAC signature: payload verification failed',
      );
    }
  }

  void _loadFallbackRules() {
    _rules = List.from(_defaultFallbackRules);
  }

  /// Compiles a raw JSON rules database into compiled memory structures.
  /// Validates the HMAC-SHA256 envelope signature before parsing rule definitions.
  void compile(String jsonStr) {
    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      verifyEnvelope(parsed);

      version = parsed['version'] as String? ?? '0.0.0';
      final payload = parsed['payload'] ?? parsed['rules'];

      List<dynamic> rawRules = [];
      if (payload is Map && payload.containsKey('rules')) {
        rawRules = payload['rules'] as List<dynamic>? ?? [];
      } else if (payload is List) {
        rawRules = payload;
      }

      _rules = rawRules
          .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on IntegrityException {
      _loadFallbackRules();
      rethrow;
    } catch (e) {
      _loadFallbackRules();
      throw IntegrityException('Failed to compile rule envelope: $e');
    }
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  void addReinforcementRule(NotificationRule rule) {
    _rules.insert(0, rule);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage and prepends them after verifying HMAC signature.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final parsed = json.decode(content) as Map<String, dynamic>;
        verifyEnvelope(parsed);

        final payload = parsed['payload'] ?? parsed['rules'];
        List<dynamic> rawList = [];
        if (payload is Map && payload.containsKey('rules')) {
          rawList = payload['rules'] as List<dynamic>? ?? [];
        } else if (payload is List) {
          rawList = payload;
        }

        final customRules = rawList
            .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();
        // Insert custom rules at the top
        _rules.insertAll(0, customRules);
      }
    } on IntegrityException catch (e) {
      // ignore: avoid_print
      print('[SECURITY AUDIT] Failed to load custom RLHF rules due to integrity failure: $e');
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to local storage encapsulated inside a signed HMAC envelope.
  Future<void> _saveCustomRules() async {
    try {
      // Filter out base rules (assuming base rules don't have 'rlhf-' prefix in id)
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final list = customRules.map((r) => r.toMap()).toList();

      final envelope = createSignedEnvelope(
        {'rules': list},
        version: version,
      );

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
