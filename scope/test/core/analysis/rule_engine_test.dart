import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
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
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('rule_engine_test_');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        },
      );

      engine = RuleEngine();
      engine.compile(sampleJson);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('compiles JSON rules and parses metadata correctly', () {
      expect(engine.version, equals('1.2.3'));
      expect(engine.totalRuleCount, equals(3));
      expect(engine.customRuleCount, equals(0));
    });

    test('compile deduplicates base rules with duplicate IDs', () {
      const String duplicateBaseJson = '''
      {
        "version": "1.0.0",
        "rules": [
          {
            "id": "dup_1",
            "category": "msg",
            "priority": "high",
            "conditions": {"keywords": ["test"]}
          },
          {
            "id": "dup_1",
            "category": "msg",
            "priority": "low",
            "conditions": {"keywords": ["test2"]}
          }
        ]
      }
      ''';
      final dupEngine = RuleEngine();
      dupEngine.compile(duplicateBaseJson);
      expect(dupEngine.totalRuleCount, equals(1));
      expect(dupEngine.rules.first.priority, equals('high'));
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

    test('addReinforcementRule prepends rule and deduplicates existing rule ID', () async {
      const ruleId = 'rlhf-1001';
      final ruleV1 = NotificationRule(
        id: ruleId,
        category: 'msg',
        priority: 'medium',
        conditions: const RuleCondition(keywords: ['hello']),
      );

      await engine.addReinforcementRule(ruleV1);
      expect(engine.totalRuleCount, equals(4));
      expect(engine.customRuleCount, equals(1));
      expect(engine.rules.first.id, equals(ruleId));
      expect(engine.rules.first.priority, equals('medium'));

      // Re-adding the same rule ID with updated priority
      final ruleV2 = NotificationRule(
        id: ruleId,
        category: 'msg',
        priority: 'high',
        conditions: const RuleCondition(keywords: ['hello', 'urgent']),
      );

      await engine.addReinforcementRule(ruleV2);
      expect(engine.totalRuleCount, equals(4));
      expect(engine.customRuleCount, equals(1));
      expect(engine.rules.first.id, equals(ruleId));
      expect(engine.rules.first.priority, equals('high'));

      // Confirm saved disk storage does not contain duplicate rules
      final file = File('${tempDir.path}/rlhf_rules.json');
      expect(await file.exists(), isTrue);
      final list = json.decode(await file.readAsString()) as List<dynamic>;
      expect(list.length, equals(1));
      expect(list.first['priority'], equals('high'));
    });

    test('addReinforcementRule ignores rules with empty ID', () async {
      final emptyRule = NotificationRule(
        id: '',
        category: 'sys',
        priority: 'low',
        conditions: const RuleCondition(keywords: ['test']),
      );

      await engine.addReinforcementRule(emptyRule);
      expect(engine.totalRuleCount, equals(3));
      expect(engine.customRuleCount, equals(0));
    });

    test('loadCustomRules prevents duplicate accumulation on multiple reloads', () async {
      const ruleId = 'rlhf-2002';
      final customRule = NotificationRule(
        id: ruleId,
        category: 'finance',
        priority: 'critical',
        conditions: const RuleCondition(keywords: ['otp']),
      );

      await engine.addReinforcementRule(customRule);
      expect(engine.customRuleCount, equals(1));

      // Reload custom rules multiple times
      await engine.loadCustomRules();
      await engine.loadCustomRules();
      await engine.loadCustomRules();

      expect(engine.customRuleCount, equals(1));
      expect(engine.totalRuleCount, equals(4));
    });

    test('loadCustomRules deduplicates rules if rlhf_rules.json contains duplicate IDs', () async {
      final file = File('${tempDir.path}/rlhf_rules.json');
      final duplicateJson = json.encode([
        {
          'id': 'rlhf-3003',
          'category': 'promo',
          'priority': 'low',
          'conditions': {'keywords': ['sale']}
        },
        {
          'id': 'rlhf-3003',
          'category': 'promo',
          'priority': 'high',
          'conditions': {'keywords': ['sale2']}
        }
      ]);
      await file.writeAsString(duplicateJson);

      await engine.loadCustomRules();

      expect(engine.customRuleCount, equals(1));
      expect(engine.rules.first.id, equals('rlhf-3003'));
      expect(engine.rules.first.priority, equals('low'));
    });

    test('loadCustomRules recovers gracefully when rlhf_rules.json is corrupt or malformed', () async {
      final file = File('${tempDir.path}/rlhf_rules.json');
      await file.writeAsString('{ invalid_json: ');

      await engine.loadCustomRules();

      expect(engine.customRuleCount, equals(0));
      expect(await file.readAsString(), equals('[]'));
    });

    test('removeReinforcementRule and clearCustomRules remove rules and sync storage', () async {
      const id1 = 'rlhf-4001';
      const id2 = 'rlhf-4002';

      await engine.addReinforcementRule(NotificationRule(
        id: id1,
        category: 'msg',
        priority: 'high',
        conditions: const RuleCondition(keywords: ['m1']),
      ));
      await engine.addReinforcementRule(NotificationRule(
        id: id2,
        category: 'social',
        priority: 'low',
        conditions: const RuleCondition(keywords: ['s1']),
      ));

      expect(engine.customRuleCount, equals(2));

      await engine.removeReinforcementRule(id1);
      expect(engine.customRuleCount, equals(1));
      expect(engine.customRules.first.id, equals(id2));

      await engine.clearCustomRules();
      expect(engine.customRuleCount, equals(0));

      final file = File('${tempDir.path}/rlhf_rules.json');
      final list = json.decode(await file.readAsString()) as List<dynamic>;
      expect(list.isEmpty, isTrue);
    });
  });
}

