import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuleEngine', () {
    const String sampleJson = '''
    {
      "version": "1.2.3",
      "rules": [
        {
          "id": "bank_debit",
          "category": "finance",
          "priority": "critical",
          "conditions": {
            "title_keywords": ["Alert", "HDFC"],
            "keywords": ["debited", "spent"]
          }
        },
        {
          "id": "whatsapp_mom",
          "category": "msg",
          "priority": "high",
          "conditions": {
            "packages": ["com.whatsapp"],
            "title_keywords": ["Mom"]
          }
        },
        {
          "id": "swiggy_promo",
          "category": "promo",
          "priority": "low",
          "conditions": {
            "keywords": ["50% off", "discount"]
          }
        }
      ]
    }
    ''';

    late RuleEngine engine;

    setUp(() {
      engine = RuleEngine();
      engine.compile(sampleJson);
    });

    test('compiles JSON rules and parses metadata correctly', () {
      expect(engine.version, equals('1.2.3'));
    });

    test('matches a debit transaction rule successfully (AND condition title+content)', () {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content: 'Your account has been debited Rs. 15,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('bank_debit'));
      expect(result.category, equals('finance'));
      expect(result.priority, equals('critical'));
      expect(result.matchedSignal, contains('Title matches "Alert"'));
      expect(result.matchedSignal, contains('Content matches "debited"'));
    });

    test('does not match debit rule if title condition is missing', () {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.random.app',
        title: 'Random notification',
        content: 'Your account was debited.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNull);
    });

    test('matches package and title keyword condition', () {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Call me back.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('whatsapp_mom'));
      expect(result.category, equals('msg'));
      expect(result.priority, equals('high'));
    });

    test('does not match package rule if package is different', () {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.instagram.android',
        title: 'Mom',
        content: 'Liked your photo',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNull);
    });

    test('matches low-priority promotional keywords', () {
      final notif = AppNotification(
        id: '3',
        packageName: 'com.swiggy',
        title: 'Delicious deals',
        content: 'Get 50% off on your first order!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      expect(result!.ruleId, equals('swiggy_promo'));
      expect(result.category, equals('promo'));
      expect(result.priority, equals('low'));
    });
  });

  group('RuleSchemaValidator & Custom Rule Validation', () {
    test('rejects custom rule without rlhf- prefix', () {
      final rule = NotificationRule(
        id: 'custom_rule_1',
        category: 'social',
        priority: 'medium',
        conditions: const RuleCondition(packages: ['com.whatsapp']),
      );
      final res = RuleSchemaValidator.validateCustomRule(rule);
      expect(res.isValid, isFalse);
      expect(res.error, contains('must start with "rlhf-"'));
    });

    test('rejects custom rule claiming reserved system rule IDs', () {
      final map = {
        'id': 'rlhf-otp_security',
        'category': 'sys',
        'priority': 'medium',
        'conditions': {
          'keywords': ['otp']
        },
      };
      final res = RuleSchemaValidator.validateCustomRuleMap(map);
      expect(res.isValid, isFalse);
      expect(res.error, contains('reserved system rule ID'));
    });

    test('rejects custom rule claiming critical priority', () {
      final rule = NotificationRule(
        id: 'rlhf-1001',
        category: 'social',
        priority: 'critical',
        conditions: const RuleCondition(packages: ['com.whatsapp']),
      );
      final res = RuleSchemaValidator.validateCustomRule(rule);
      expect(res.isValid, isFalse);
      expect(res.error, contains('cannot claim critical priority'));
    });

    test('rejects custom rule with empty condition set wildcard', () {
      final rule = NotificationRule(
        id: 'rlhf-1002',
        category: 'social',
        priority: 'low',
        conditions: const RuleCondition(packages: [], keywords: [], titleKeywords: []),
      );
      final res = RuleSchemaValidator.validateCustomRule(rule);
      expect(res.isValid, isFalse);
      expect(res.error, contains('empty condition wildcard'));
    });

    test('rejects custom rule containing empty keyword string wildcard', () {
      final map = {
        'id': 'rlhf-1003',
        'category': 'promo',
        'priority': 'low',
        'conditions': {
          'keywords': [''],
        },
      };
      final res = RuleSchemaValidator.validateCustomRuleMap(map);
      expect(res.isValid, isFalse);
      expect(res.error, contains('empty keyword string wildcard'));
    });

    test('rejects duplicate custom rule IDs', () {
      final rule = NotificationRule(
        id: 'rlhf-1004',
        category: 'social',
        priority: 'low',
        conditions: const RuleCondition(packages: ['com.instagram.android']),
      );
      final existingIds = {'rlhf-1004'};
      final res = RuleSchemaValidator.validateCustomRule(rule, existingIds: existingIds);
      expect(res.isValid, isFalse);
      expect(res.error, contains('duplicate ID'));
    });

    test('accepts valid custom rule', () {
      final rule = NotificationRule(
        id: 'rlhf-2001',
        category: 'social',
        priority: 'high',
        conditions: const RuleCondition(
          packages: ['com.instagram.android'],
          keywords: ['tagged'],
        ),
      );
      final res = RuleSchemaValidator.validateCustomRule(rule);
      expect(res.isValid, isTrue);
    });
  });

  group('Tiered Rule Engine Pipeline & Precedence', () {
    test('system rules evaluate prior to any custom user rules', () {
      final engine = RuleEngine();
      engine.compile('''
      {
        "version": "1.0.0",
        "rules": [
          {
            "id": "otp_security",
            "category": "sys",
            "priority": "critical",
            "conditions": {
              "keywords": ["verification code", "otp"]
            }
          }
        ]
      }
      ''');

      final customRule = NotificationRule(
        id: 'rlhf-whatsapp-mute',
        category: 'msg',
        priority: 'low',
        conditions: const RuleCondition(
          packages: ['com.whatsapp'],
        ),
      );
      final added = engine.addReinforcementRule(customRule);
      expect(added, isTrue);

      final notif = AppNotification(
        id: '100',
        packageName: 'com.whatsapp',
        title: 'WhatsApp Code',
        content: 'Your verification code is 882715.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final match = engine.match(notif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('otp_security'));
      expect(match.tier, equals(RuleTier.system));
      expect(match.priority, equals('critical'));
    });

    test('addReinforcementRule rejects invalid custom rule payload', () {
      final engine = RuleEngine();
      engine.compile('{"version": "1.0", "rules": []}');

      final invalidRule = NotificationRule(
        id: 'otp_security',
        category: 'sys',
        priority: 'critical',
        conditions: const RuleCondition(),
      );

      final added = engine.addReinforcementRule(invalidRule);
      expect(added, isFalse);
      expect(engine.customRules, isEmpty);
    });
  });

  group('Score Fusion Tier Authority', () {
    test('system tier critical rule grants score 1.0 security bypass', () {
      final systemMatch = const MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'Content matches "otp"',
        tier: RuleTier.system,
      );
      final modelResult = const AnalysisResult(
        category: 'msg',
        score: 0.35,
        engineName: 'ml',
        matchedSignals: [],
        latencyMs: 0,
      );

      final fused = ScoreFusion.fuse(ruleResult: systemMatch, modelResult: modelResult);
      expect(fused.score, equals(1.0));
      expect(fused.engineName, contains('rule bypass'));
    });

    test('custom tier rule does NOT grant critical security bypass', () {
      final customMatch = const MatchedRuleResult(
        ruleId: 'rlhf-fake-otp',
        category: 'sys',
        priority: 'high',
        matchedSignal: 'Content matches "otp"',
        tier: RuleTier.custom,
      );
      final modelResult = const AnalysisResult(
        category: 'msg',
        score: 0.35,
        engineName: 'ml',
        matchedSignals: [],
        latencyMs: 0,
      );

      final fused = ScoreFusion.fuse(ruleResult: customMatch, modelResult: modelResult);
      expect(fused.score, isNot(equals(1.0)));
      expect(fused.engineName, equals('score_fusion (hybrid)'));
    });
  });

  group('Performance & Execution Latency Benchmark', () {
    test('rule evaluation latency per notification is under 0.5ms', () {
      final engine = RuleEngine();
      engine.compile('''
      {
        "version": "1.0.0",
        "rules": [
          {
            "id": "otp_security",
            "category": "sys",
            "priority": "critical",
            "conditions": {"keywords": ["otp", "verification code"]}
          },
          {
            "id": "finance_debit",
            "category": "finance",
            "priority": "critical",
            "conditions": {"keywords": ["debited", "spent"]}
          }
        ]
      }
      ''');

      final notif = AppNotification(
        id: 'perf_1',
        packageName: 'com.whatsapp',
        title: 'Verification Code',
        content: 'Your security OTP verification code is 554321.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final stopwatch = Stopwatch()..start();
      const iterations = 1000;
      for (int i = 0; i < iterations; i++) {
        engine.match(notif);
      }
      stopwatch.stop();

      final avgLatencyUs = stopwatch.elapsedMicroseconds / iterations;
      final avgLatencyMs = avgLatencyUs / 1000.0;
      expect(avgLatencyMs, lessThan(0.5));
    });
  });
}

