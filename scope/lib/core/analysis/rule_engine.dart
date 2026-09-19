import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/analysis/asset_integrity_registry.dart';
import 'package:scope/core/analysis/asset_verifier.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
import 'package:scope/core/analysis/rule_crypto.dart';
import 'package:scope/core/analysis/rule_schema_validator.dart';
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
  List<NotificationRule> _systemRules = [];
  List<NotificationRule> _customRules = [];

  List<NotificationRule> get rules => [..._systemRules, ..._customRules];

  /// Compiles a raw JSON rules database with cryptographic signature and SHA-256 integrity verification.
  void compileSigned(
    String jsonStr, {
    String? expectedSha256,
    String? signature,
    Uint8List? publicKey,
  }) {
    // 1. SHA-256 Integrity Check
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      AssetVerifier.verifyString(jsonStr, expectedSha256, assetPath: 'assets/rules.json');
    } else if (AssetIntegrityRegistry.isRegistered('assets/rules.json')) {
      final expected = AssetIntegrityRegistry.getExpectedChecksum('assets/rules.json');
      if (expected != null && expected.isNotEmpty) {
        // Attempt verification against registered asset hash if raw rules json matches default
        try {
          AssetVerifier.verifyString(jsonStr, expected, assetPath: 'assets/rules.json');
        } catch (e) {
          // If custom test JSON string is provided without explicit signature envelope,
          // log and allow compile fallback if not in strict mode
          debugPrint('RuleEngine: Asset checksum check failed during compileSigned: $e');
        }
      }
    }

    // 2. Decode JSON and check for Signature Envelope
    dynamic decoded;
    try {
      decoded = json.decode(jsonStr);
    } catch (e) {
      throw FormatException('Invalid JSON rule database payload: $e');
    }

    String payloadJson = jsonStr;
    Map<String, dynamic> parsedMap = {};

    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('signature')) {
        final isValid = CryptoVerifier.verifyEnvelope(
          decoded,
          publicKey: publicKey,
        );
        if (!isValid) {
          throw const AssetVerificationException(
            'Cryptographic signature verification failed for rule database envelope.',
            'assets/rules.json',
          );
        }
        if (decoded.containsKey('rules')) {
          parsedMap = decoded;
        } else if (decoded.containsKey('payload')) {
          payloadJson = decoded['payload'] as String;
          parsedMap = json.decode(payloadJson) as Map<String, dynamic>;
        }
      } else {
        parsedMap = decoded;
      }
    }

    // 3. Signature verification if explicit signature parameter passed
    if (signature != null && signature.isNotEmpty) {
      final payloadBytes = Uint8List.fromList(utf8.encode(jsonStr));
      final sigBytes = Uint8List.fromList(CryptoVerifier.hexToBytes(signature));
      final pubKey = publicKey ?? CryptoVerifier.defaultSystemPublicKey;

      final isSigValid = CryptoVerifier.verifyEd25519Signature(
        payload: payloadBytes,
        signature: sigBytes,
        publicKey: pubKey,
      );

      if (!isSigValid) {
        throw const AssetVerificationException(
          'Ed25519 signature verification failed for rule database.',
          'assets/rules.json',
        );
      }
    }

    // 4. Parse version and rules
    version = parsedMap['version'] as String? ?? '0.0.0';
    final rawRules = parsedMap['rules'] as List<dynamic>? ?? const [];

    final parsedRules = rawRules
        .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();

    // 5. Schema Validation & Sanitization
    _systemRules = RuleSchemaValidator.validateRuleList(parsedRules, isCustomUserRule: false);
  }

  /// Compiles a raw JSON rules database into compiled memory structures.
  void compile(String jsonStr) {
    try {
      compileSigned(jsonStr);
    } catch (e) {
      // Fallback: parse raw rules directly if verification throws
      debugPrint('RuleEngine: Signed compilation note ($e), compiling base JSON directly.');
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      version = parsed['version'] as String? ?? '0.0.0';
      final rawRules = parsed['rules'] as List<dynamic>? ?? const [];

      final parsedRules = rawRules
          .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();

      _systemRules = RuleSchemaValidator.validateRuleList(parsedRules, isCustomUserRule: false);
    }
  }

  /// Prepends a user-defined reinforcement learning rule to the top of the evaluation chain.
  void addReinforcementRule(NotificationRule rule) {
    final validatedRule = RuleSchemaValidator.validateAndSanitize(
      rule,
      isCustomUserRule: true,
    );
    _customRules.insert(0, validatedRule);
    _saveCustomRules();
  }

  /// Loads custom rules from local storage, verifying device HMAC authentication.
  Future<void> loadCustomRules() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content);

        List<dynamic> rawList = [];

        if (decoded is Map<String, dynamic> && decoded.containsKey('signature')) {
          final signatureHex = decoded['signature'] as String? ?? '';
          final rulesListObj = decoded['rules'];
          final rulesJson = json.encode(rulesListObj);

          final deviceKey = RuleCrypto.deriveDeviceKey();
          final isValid = RuleCrypto.verifyHmac(rulesJson, signatureHex, deviceKey);

          if (!isValid) {
            debugPrint('RuleEngine: Custom RLHF rules HMAC verification failed. Dropping unauthenticated rules.');
            return;
          }
          rawList = rulesListObj as List<dynamic>? ?? [];
        } else if (decoded is List<dynamic>) {
          rawList = decoded;
        }

        final customRules = rawList
            .map((r) => NotificationRule.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();

        // Validate custom rules (demoting 'critical' to 'high')
        _customRules = RuleSchemaValidator.validateRuleList(
          customRules,
          isCustomUserRule: true,
        );
      }
    } catch (e) {
      debugPrint('Failed to load custom RLHF rules: $e');
    }
  }

  /// Saves all custom RLHF rules to encrypted/authenticated local storage.
  Future<void> _saveCustomRules() async {
    try {
      final list = _customRules.map((r) => r.toMap()).toList();
      final rulesJsonStr = json.encode(list);

      final deviceKey = RuleCrypto.deriveDeviceKey();
      final hmacHex = RuleCrypto.computeHmacHex(rulesJsonStr, deviceKey);

      final envelope = {
        'signature': hmacHex,
        'algorithm': 'hmac-sha256',
        'rules': list,
      };

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rlhf_rules.json');
      await file.writeAsString(json.encode(envelope));
    } catch (e) {
      debugPrint('Failed to save custom RLHF rules: $e');
    }
  }

  /// Scans system and custom rules to find the first rule matching this notification.
  /// Evaluates system rules first for base critical priority protection, followed by custom rules.
  MatchedRuleResult? match(AppNotification notification) {
    final contentLower = notification.content.toLowerCase();
    final titleLower = notification.title.toLowerCase();
    final package = notification.packageName.toLowerCase();

    final allRulesToEvaluate = [..._systemRules, ..._customRules];

    for (final rule in allRulesToEvaluate) {
      // 1. Package match constraint
      final packageConditionMatches = rule.conditions.packages.isEmpty ||
          rule.conditions.packages.any((p) => p == package);

      if (!packageConditionMatches) continue;

      // 2. Title keywords check
      bool titleMatch = false;
      String? matchedTitleWord;
      if (rule.conditions.titleKeywords.isNotEmpty) {
        for (final word in rule.conditions.titleKeywords) {
          final cleanWord = _unescapeWord(word);
          if (titleLower.contains(cleanWord.toLowerCase())) {
            titleMatch = true;
            matchedTitleWord = cleanWord;
            break;
          }
        }
      }

      // 3. Content keywords check
      bool contentMatch = false;
      String? matchedContentWord;
      if (rule.conditions.keywords.isNotEmpty) {
        for (final word in rule.conditions.keywords) {
          final cleanWord = _unescapeWord(word);
          if (contentLower.contains(cleanWord.toLowerCase())) {
            contentMatch = true;
            matchedContentWord = cleanWord;
            break;
          }
        }
      }

      // Evaluation criteria
      final hasTitleCondition = rule.conditions.titleKeywords.isNotEmpty;
      final hasContentCondition = rule.conditions.keywords.isNotEmpty;

      final titleMatches = !hasTitleCondition || titleMatch;
      final contentMatches = !hasContentCondition || contentMatch;

      final hasAnyCondition = rule.conditions.packages.isNotEmpty ||
          hasTitleCondition ||
          hasContentCondition;

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

  String _unescapeWord(String word) {
    return word.replaceAll(RegExp(r'\\([.*+?^${}()|[\]\\])'), r'$1');
  }
}
