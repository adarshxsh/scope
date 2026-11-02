import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
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
  String version = '0.0.0-safe-fallback';
  List<NotificationRule> _rules = List<NotificationRule>.from(safeDefaultRules);

  List<NotificationRule> get rules => List.unmodifiable(_rules);

  /// Hardcoded safe default rules applied as fallback if verification fails.
  static final List<NotificationRule> safeDefaultRules = [
    NotificationRule(
      id: 'default_otp_security',
      category: 'sys',
      priority: 'critical',
      conditions: const RuleCondition(
        keywords: ['otp', 'verification code', 'one-time password', 'security code'],
      ),
    ),
    NotificationRule(
      id: 'default_finance_debit',
      category: 'finance',
      priority: 'critical',
      conditions: const RuleCondition(
        keywords: ['debited', 'withdrawn', 'spent', 'deducted', 'sent rs', 'sent inr', 'charge'],
        titleKeywords: ['alert', 'bank', 'charge', 'card'],
      ),
    ),
    NotificationRule(
      id: 'default_promo_deals',
      category: 'promo',
      priority: 'low',
      conditions: const RuleCondition(
        keywords: ['sale', '50% off', 'discount', 'deal', 'coupon', 'promo', 'free delivery', 'shop now', 'cashback', 'limited time'],
      ),
    ),
  ];

  /// Compiles a raw JSON rules database envelope into compiled memory structures.
  /// Validates Ed25519 signature before parsing payload objects.
  Future<void> compile(String jsonStr) async {
    try {
      final parsed = json.decode(jsonStr);
      if (parsed is! Map<String, dynamic>) {
        _applySafeFallback('Rule manifest is not a valid JSON map object.');
        throw RuleVerificationException('Malformed rule manifest JSON structure.');
      }

      final hasSignature = parsed.containsKey('signature') && parsed['signature'] is String;
      final hasKeyId = parsed.containsKey('key_id') && parsed['key_id'] is String;
      final hasPayload = parsed.containsKey('payload') && parsed['payload'] is Map<String, dynamic>;

      if (!hasSignature || !hasKeyId || !hasPayload) {
        _applySafeFallback('Rule database manifest missing mandatory cryptographic signature envelope.');
        throw RuleVerificationException(
          'Rule database manifest missing mandatory cryptographic signature envelope (signature, key_id, payload).',
        );
      }

      final sigAlg = parsed['signature_algorithm'] as String? ?? '';
      if (sigAlg != 'Ed25519') {
        _applySafeFallback('Unsupported signature algorithm "$sigAlg".');
        throw RuleVerificationException('Unsupported signature algorithm: $sigAlg.');
      }

      final keyId = parsed['key_id'] as String;
      final signatureBase64 = parsed['signature'] as String;
      final payloadMap = parsed['payload'] as Map<String, dynamic>;

      final payloadBytes = utf8.encode(jsonEncode(payloadMap));

      final isValid = await CryptoVerifier.verifyEd25519Signature(
        payloadBytes: payloadBytes,
        signatureBase64: signatureBase64,
        keyId: keyId,
      );

      if (!isValid) {
        _applySafeFallback('Ed25519 signature verification failed or payload tampered for key_id "$keyId".');
        throw RuleVerificationException(
          'Ed25519 signature verification failed for rule manifest (key_id: $keyId).',
        );
      }

      version = payloadMap['version'] as String? ?? '0.0.0';
      final rawRules = payloadMap['rules'] as List<dynamic>? ?? const [];
      _rules = rawRules
          .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      if (e is RuleVerificationException) {
        rethrow;
      }
      _applySafeFallback('Unhandled rule compilation error: $e');
      throw RuleVerificationException('Failed to compile rule manifest: $e');
    }
  }

  /// Compiles signed rule specifications, pinned with an optional trusted public key.
  Future<void> compileSigned(String jsonStr, {String? publicKeyBase64}) async {
    if (publicKeyBase64 != null) {
      try {
        final parsed = json.decode(jsonStr) as Map<String, dynamic>;
        final keyId = parsed['key_id'] as String? ?? 'scope-prod-key-1';
        CryptoVerifier.addTrustedPublicKey(keyId, publicKeyBase64);
      } catch (_) {}
    }
    return compile(jsonStr);
  }

  void _applySafeFallback(String reason) {
    debugPrint('[SECURITY AUDIT] $reason Falling back to safe default rules.');
    _rules = List<NotificationRule>.from(safeDefaultRules);
    version = '0.0.0-safe-fallback';
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  Future<void> addReinforcementRule(NotificationRule rule) async {
    _rules.insert(0, rule);
    await _saveCustomRules();
  }

  /// Loads custom rules from local storage and prepends them after validating HMAC-SHA256 signature.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = json.decode(content);

        if (map is Map<String, dynamic> &&
            map['signature_algorithm'] == 'HMAC-SHA256' &&
            map.containsKey('signature') &&
            map.containsKey('payload')) {
          final signatureBase64 = map['signature'] as String;
          final payload = map['payload'] as List<dynamic>;
          final payloadBytes = utf8.encode(jsonEncode(payload));
          final deviceKey = CryptoVerifier.deriveDeviceKey();

          final isValid = CryptoVerifier.verifyHmac(payloadBytes, signatureBase64, deviceKey);
          if (isValid) {
            final customRules = payload
                .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
                .toList();
            _rules.insertAll(0, customRules);
            debugPrint('Successfully loaded ${customRules.length} device-signed RLHF custom rules.');
          } else {
            debugPrint(
              '[SECURITY AUDIT] Local RLHF rules HMAC-SHA256 signature mismatch (file tampered). Ignoring custom rules.',
            );
          }
        } else {
          debugPrint(
            '[SECURITY AUDIT] Local RLHF rules file missing HMAC signature envelope. Ignoring custom rules.',
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to local storage using device-bound HMAC-SHA256 signature envelope.
  Future<void> _saveCustomRules() async {
    try {
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final payload = customRules.map((r) => r.toMap()).toList();
      final payloadBytes = utf8.encode(jsonEncode(payload));
      final deviceKey = CryptoVerifier.deriveDeviceKey();
      final signatureBase64 = CryptoVerifier.signHmac(payloadBytes, deviceKey);

      final enveloped = {
        'version': '1.0.0',
        'signature_algorithm': 'HMAC-SHA256',
        'signature': signatureBase64,
        'payload': payload,
      };

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(enveloped));
    } catch (e) {
      debugPrint('Failed to save custom RLHF rules: $e');
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
