import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
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

    group('RLHF Custom Rule Deduplication and Persistence', () {
      late Directory tempDir;

      setUp(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        tempDir = await Directory.systemTemp.createTemp(
          'rule_engine_test_',
        );

        const channel = MethodChannel('plugins.flutter.io/path_provider');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
      });

      tearDown(() async {
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'addReinforcementRule removes existing rule with matching id and prepends new rule at index 0',
        () async {
          final customRule1 = NotificationRule(
            id: 'rlhf-1',
            category: 'promo',
            priority: 'low',
            conditions: const RuleCondition(keywords: ['sale']),
          );

          final customRule1Updated = NotificationRule(
            id: 'rlhf-1',
            category: 'finance',
            priority: 'critical',
            conditions: const RuleCondition(keywords: ['sale']),
          );

          engine.addReinforcementRule(customRule1);
          expect(engine.rules.length, equals(4));
          expect(engine.rules.first.id, equals('rlhf-1'));
          expect(engine.rules.first.priority, equals('low'));

          // Add updated rule with same identifier
          engine.addReinforcementRule(customRule1Updated);
          expect(engine.rules.length, equals(4)); // count unchanged
          expect(engine.rules.first.id, equals('rlhf-1'));
          expect(engine.rules.first.priority, equals('critical'));
          expect(
            engine.rules.where((r) => r.id == 'rlhf-1').length,
            equals(1),
          );
        },
      );

      test(
        'addReinforcementRule removes matching base rule and places custom rule at index 0',
        () async {
          final overrideBaseRule = NotificationRule(
            id: 'bank_debit',
            category: 'msg',
            priority: 'low',
            conditions: const RuleCondition(keywords: ['debited']),
          );

          engine.addReinforcementRule(overrideBaseRule);
          expect(engine.rules.length, equals(3));
          expect(engine.rules.first.id, equals('bank_debit'));
          expect(engine.rules.first.priority, equals('low'));
          expect(
            engine.rules.where((r) => r.id == 'bank_debit').length,
            equals(1),
          );
        },
      );

      test(
        'loadCustomRules deduplicates rules against existing in-memory rules and disk file duplicates',
        () async {
          // Add rlhf-1 to memory before loading
          engine.addReinforcementRule(
            NotificationRule(
              id: 'rlhf-1',
              category: 'old_cat',
              priority: 'low',
              conditions: const RuleCondition(),
            ),
          );

          // Allow pending _saveCustomRules write to complete before overwriting file
          await Future.delayed(Duration.zero);

          final ruleFile = File('${tempDir.path}/rlhf_rules.json');
          final fileContent = jsonEncode([
            {
              'id': 'rlhf-1',
              'category': 'finance',
              'priority': 'high',
              'conditions': {'keywords': ['invoice']}
            },
            {
              'id': 'rlhf-1', // duplicate in file
              'category': 'finance',
              'priority': 'low',
              'conditions': {'keywords': ['invoice']}
            },
            {
              'id': 'rlhf-2',
              'category': 'promo',
              'priority': 'low',
              'conditions': {'keywords': ['discount']}
            }
          ]);
          await ruleFile.writeAsString(fileContent);

          expect(
            engine.rules.where((r) => r.id == 'rlhf-1').length,
            equals(1),
          );

          // Now load custom rules from storage
          await engine.loadCustomRules();

          // Total rules should be 3 base rules + 2 unique custom rules = 5
          expect(engine.rules.length, equals(5));
          expect(
            engine.rules.where((r) => r.id == 'rlhf-1').length,
            equals(1),
          );
          expect(
            engine.rules.where((r) => r.id == 'rlhf-2').length,
            equals(1),
          );
          // First custom rule loaded should take precedence and be at top
          expect(engine.rules[0].id, equals('rlhf-1'));
          expect(engine.rules[0].priority, equals('high'));
          expect(engine.rules[1].id, equals('rlhf-2'));
        },
      );

      test('persisted rlhf_rules.json contains strictly unique custom rules', () async {
        final customRule1 = NotificationRule(
          id: 'rlhf-1',
          category: 'promo',
          priority: 'low',
          conditions: const RuleCondition(keywords: ['deal']),
        );

        final customRule2 = NotificationRule(
          id: 'rlhf-2',
          category: 'msg',
          priority: 'high',
          conditions: const RuleCondition(keywords: ['urgent']),
        );

        engine.addReinforcementRule(customRule1);
        engine.addReinforcementRule(customRule2);
        // Re-add customRule1 with updated priority
        final customRule1Updated = NotificationRule(
          id: 'rlhf-1',
          category: 'promo',
          priority: 'critical',
          conditions: const RuleCondition(keywords: ['deal']),
        );
        engine.addReinforcementRule(customRule1Updated);

        // Allow any pending async file writes to flush
        await Future.delayed(Duration.zero);

        final ruleFile = File('${tempDir.path}/rlhf_rules.json');
        expect(ruleFile.existsSync(), isTrue);

        final list = jsonDecode(await ruleFile.readAsString()) as List<dynamic>;
        expect(list.length, equals(2));

        final ids = list.map((r) => (r as Map)['id'] as String).toList();
        expect(ids.toSet().length, equals(ids.length));
        expect(ids, containsAll(['rlhf-1', 'rlhf-2']));
      });
    });
  });
}
