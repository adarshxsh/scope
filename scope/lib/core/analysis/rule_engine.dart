import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
import 'package:scope/core/analysis/embedded_keys.dart';
import 'package:scope/core/models/notification_model.dart';

/// Exception thrown when cryptographic signature verification or envelope validation fails.
class SignatureVerificationException implements Exception {
  final String message;
  final String? keyId;
  final String? algorithm;

  SignatureVerificationException(this.message, {this.keyId, this.algorithm});

  @override
  String toString() =>
      'SignatureVerificationException: $message (keyId: $keyId, algorithm: $algorithm)';
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

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    _compileParsedMap(parsed);
  }

  /// Extracts envelope, computes SHA-256 payload digest, verifies signature using bundled public key, and compiles rules.
  void compileSigned(String signedJsonStr) {
    final stopwatch = Stopwatch()..start();

    Map<String, dynamic> envelope;
    try {
      envelope = json.decode(signedJsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw SignatureVerificationException('Malformed envelope JSON: $e');
    }

    final signerId =
        envelope['signer_id'] as String? ?? envelope['key_id'] as String?;
    final algorithm = envelope['algorithm'] as String?;
    final signatureBase64 = envelope['signature'] as String?;
    final rawPayload = envelope['payload'];

    if (signerId == null || signerId.isEmpty) {
      throw SignatureVerificationException('Missing signer_id in rule envelope');
    }
    if (algorithm == null || algorithm.isEmpty) {
      throw SignatureVerificationException('Missing algorithm in rule envelope', keyId: signerId);
    }
    if (signatureBase64 == null || signatureBase64.isEmpty) {
      throw SignatureVerificationException('Missing signature in rule envelope', keyId: signerId, algorithm: algorithm);
    }
    if (rawPayload == null) {
      throw SignatureVerificationException('Missing payload in rule envelope', keyId: signerId, algorithm: algorithm);
    }

    final keyMeta = EmbeddedKeys.getKey(signerId);
    if (keyMeta == null) {
      throw SignatureVerificationException(
        'Public verification key "$signerId" not found, inactive, or revoked',
        keyId: signerId,
        algorithm: algorithm,
      );
    }

    if (keyMeta.algorithm.toUpperCase() != algorithm.toUpperCase()) {
      throw SignatureVerificationException(
        'Key algorithm mismatch: expected ${keyMeta.algorithm}, got $algorithm',
        keyId: signerId,
        algorithm: algorithm,
      );
    }

    final List<int> payloadBytes = utf8.encode(
      rawPayload is String ? rawPayload : json.encode(rawPayload),
    );
    final payloadDigest = CryptoVerifier.computeSha256Digest(payloadBytes);

    final isValid = CryptoVerifier.verifySignature(
      algorithm: algorithm,
      publicKey: keyMeta.publicKey,
      signatureBase64: signatureBase64,
      payloadBytes: payloadBytes,
    );

    stopwatch.stop();

    if (!isValid) {
      throw SignatureVerificationException(
        'Cryptographic signature verification failed (SHA-256 digest: ${payloadDigest.toString().substring(0, 16)}...)',
        keyId: signerId,
        algorithm: algorithm,
      );
    }

    if (stopwatch.elapsedMilliseconds > 5) {
      debugPrint('RuleEngine WARNING: Signature verification took ${stopwatch.elapsedMilliseconds} ms (> 5 ms limit)');
    }

    if (rawPayload is String) {
      compile(rawPayload);
    } else if (rawPayload is Map) {
      _compileParsedMap(Map<String, dynamic>.from(rawPayload));
    } else {
      throw SignatureVerificationException('Invalid payload format in envelope', keyId: signerId, algorithm: algorithm);
    }

    debugPrint('RuleEngine: Verified and compiled signed rules (version: $version, time: ${stopwatch.elapsedMicroseconds} us).');
  }

  void _compileParsedMap(Map<String, dynamic> parsed) {
    version = parsed['version'] as String? ?? '0.0.0';
    final rawRules = parsed['rules'] as List<dynamic>? ?? const [];
    _rules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Populates RuleEngine with hardcoded core fallback rules when asset signature verification fails.
  void loadDefaultFallbackRules() {
    version = '1.0.0-fallback';
    _rules = [
      const NotificationRule(
        id: 'fallback_otp',
        category: 'sys',
        priority: 'critical',
        conditions: RuleCondition(
          keywords: ['otp', 'verification code', 'one-time password', 'security code'],
        ),
      ),
      const NotificationRule(
        id: 'fallback_finance',
        category: 'finance',
        priority: 'critical',
        conditions: RuleCondition(
          titleKeywords: ['bank', 'alert', 'card'],
          keywords: ['debited', 'withdrawn', 'spent', 'sent inr', 'deducted'],
        ),
      ),
      const NotificationRule(
        id: 'fallback_promo',
        category: 'promo',
        priority: 'low',
        conditions: RuleCondition(
          keywords: ['sale', 'discount', '50% off', 'promo', 'coupon'],
        ),
      ),
    ];
    debugPrint('RuleEngine: Loaded core fallback rules (version: $version).');
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  void addReinforcementRule(NotificationRule rule) {
    _rules.insert(0, rule);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage, verifying local HMAC signature guardrail.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final envelope = json.decode(content) as Map<String, dynamic>;

        final signerId = envelope['signer_id'] as String? ?? 'scope-rlhf-local-key';
        final algorithm = envelope['algorithm'] as String? ?? 'HMAC-SHA256';
        final signatureBase64 = envelope['signature'] as String? ?? '';
        final rawPayload = envelope['payload'];

        final keyMeta = EmbeddedKeys.getKey(signerId);
        if (keyMeta == null) {
          debugPrint('RuleEngine: Local RLHF key "$signerId" not found or revoked.');
          return;
        }

        final payloadBytes = utf8.encode(
          rawPayload is String ? rawPayload : json.encode(rawPayload),
        );

        final isValid = CryptoVerifier.verifySignature(
          algorithm: algorithm,
          publicKey: keyMeta.publicKey,
          signatureBase64: signatureBase64,
          payloadBytes: payloadBytes,
        );

        if (!isValid) {
          debugPrint('SECURITY WARNING: Custom RLHF rules signature verification failed. Rejecting untrusted custom rules.');
          return;
        }

        List<dynamic> list;
        if (rawPayload is List) {
          list = rawPayload;
        } else if (rawPayload is String) {
          list = json.decode(rawPayload) as List<dynamic>;
        } else {
          return;
        }

        final customRules = list
            .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();

        _rules.insertAll(0, customRules);
      }
    } catch (e) {
      debugPrint('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves custom RLHF rules to local storage wrapped in an HMAC guardrail envelope.
  Future<void> _saveCustomRules() async {
    try {
      final customRules = _rules.where((r) => r.id.startsWith('rlhf-')).toList();
      final list = customRules.map((r) => r.toMap()).toList();

      const signerId = 'scope-rlhf-local-key';
      final keyMeta = EmbeddedKeys.getKey(signerId);
      if (keyMeta == null) return;

      final payloadBytes = utf8.encode(json.encode(list));
      final sigBase64 = CryptoVerifier.signHmacSha256(keyMeta.publicKey, payloadBytes);

      final envelope = {
        'signer_id': signerId,
        'algorithm': 'HMAC-SHA256',
        'signature': sigBase64,
        'payload': list,
      };

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(envelope));
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
      final packageConditionMatches =
          rule.conditions.packages.isEmpty || rule.conditions.packages.contains(package);

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
        );
      }
    }

    return null;
  }
}
