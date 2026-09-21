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
    const channel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      engine = RuleEngine();
      engine.compile(sampleJson);

      tempDir = await Directory.systemTemp.createTemp('rule_engine_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
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

    group('Schema Validation & Bounds', () {
      test('validates NotificationRule schema bounds correctly', () {
        final validRule = NotificationRule(
          id: 'rlhf-1',
          category: 'finance',
          priority: 'high',
          conditions: const RuleCondition(
            packages: ['com.bank.app'],
            keywords: ['transfer', 'sent'],
          ),
        );
        expect(validRule.isValid, isTrue);

        final invalidCategoryRule = NotificationRule(
          id: 'rlhf-2',
          category: 'invalid_category_xyz',
          priority: 'high',
          conditions: const RuleCondition(keywords: ['test']),
        );
        expect(invalidCategoryRule.isValid, isFalse);

        final invalidPriorityRule = NotificationRule(
          id: 'rlhf-3',
          category: 'finance',
          priority: 'super_critical',
          conditions: const RuleCondition(keywords: ['test']),
        );
        expect(invalidPriorityRule.isValid, isFalse);

        final oversizedKeywordRule = NotificationRule(
          id: 'rlhf-4',
          category: 'finance',
          priority: 'high',
          conditions: RuleCondition(
            keywords: ['a' * 101],
          ),
        );
        expect(oversizedKeywordRule.isValid, isFalse);

        final oversizedArrayRule = NotificationRule(
          id: 'rlhf-5',
          category: 'finance',
          priority: 'high',
          conditions: RuleCondition(
            keywords: List.generate(11, (i) => 'keyword_$i'),
          ),
        );
        expect(oversizedArrayRule.isValid, isFalse);
      });

      test('addReinforcementRule rejects invalid rules and respects max 50 custom rules capacity', () {
        final invalidRule = NotificationRule(
          id: 'rlhf-invalid',
          category: 'finance',
          priority: 'high',
          conditions: RuleCondition(
            keywords: List.generate(15, (i) => 'kw_$i'), // > 10 keywords
          ),
        );

        expect(engine.addReinforcementRule(invalidRule), isFalse);

        // Add 50 valid custom rules
        for (int i = 0; i < 50; i++) {
          final rule = NotificationRule(
            id: 'rlhf-rule-$i',
            category: 'msg',
            priority: 'medium',
            conditions: RuleCondition(keywords: ['word_$i']),
          );
          expect(engine.addReinforcementRule(rule), isTrue);
        }

        // 51st custom rule should be rejected
        final rule51 = NotificationRule(
          id: 'rlhf-rule-51',
          category: 'msg',
          priority: 'medium',
          conditions: const RuleCondition(keywords: ['extra_word']),
        );
        expect(engine.addReinforcementRule(rule51), isFalse);
      });

      test('loadCustomRules parses rlhf_rules.json safely and drops entries violating bounds', () async {
        final rlhfFile = File('${tempDir.path}/rlhf_rules.json');
        final rawJson = json.encode([
          {
            'id': 'rlhf-valid-1',
            'category': 'finance',
            'priority': 'high',
            'conditions': {
              'keywords': ['valid_kw']
            }
          },
          {
            'id': 'rlhf-invalid-kw-len',
            'category': 'finance',
            'priority': 'high',
            'conditions': {
              'keywords': ['x' * 105] // violates length bound
            }
          },
          {
            'id': 'rlhf-invalid-kw-count',
            'category': 'finance',
            'priority': 'high',
            'conditions': {
              'keywords': List.generate(12, (i) => 'kw_$i') // violates array count bound
            }
          },
          {
            'id': 'rlhf-invalid-priority',
            'category': 'finance',
            'priority': 'unknown_prio', // violates enum bound
            'conditions': {
              'keywords': ['test']
            }
          }
        ]);
        await rlhfFile.writeAsString(rawJson);

        await engine.loadCustomRules();

        final customRules = engine.rules.where((r) => r.id.startsWith('rlhf-')).toList();
        expect(customRules.length, equals(1));
        expect(customRules.first.id, equals('rlhf-valid-1'));

        final quarantineFile = File('${tempDir.path}/rlhf_rules.quarantine.json');
        expect(await quarantineFile.exists(), isTrue);
      });

      test('loadCustomRules quarantines corrupted JSON files without crashing', () async {
        final rlhfFile = File('${tempDir.path}/rlhf_rules.json');
        await rlhfFile.writeAsString('{{{ INVALID JSON STRUCTURE }');

        await engine.loadCustomRules();

        final customRules = engine.rules.where((r) => r.id.startsWith('rlhf-')).toList();
        expect(customRules, isEmpty);

        final quarantineFile = File('${tempDir.path}/rlhf_rules.quarantine.json');
        expect(await quarantineFile.exists(), isTrue);
      });

      test('match handles condition evaluation errors gracefully', () {
        final throwingRule = NotificationRule(
          id: 'rlhf-throwing',
          category: 'finance',
          priority: 'high',
          conditions: const RuleCondition(
            keywords: ['debited'],
          ),
        );
        engine.addReinforcementRule(throwingRule);

        final notif = AppNotification(
          id: 'test_id',
          packageName: 'com.hdfc.mobilebanking',
          title: 'HDFC Alert',
          content: 'Your account has been debited Rs. 500.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = engine.match(notif);
        expect(result, isNotNull);
      });
    });
  });
}
