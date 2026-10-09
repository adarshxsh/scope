import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

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

    test('deduplicates reinforcement rules when added multiple times with same ID', () {
      const ruleId = 'rlhf-1001';
      final rule1 = NotificationRule(
        id: ruleId,
        category: 'msg',
        priority: 'high',
        conditions: RuleCondition(keywords: ['urgent']),
      );

      final rule2 = NotificationRule(
        id: ruleId,
        category: 'msg',
        priority: 'critical',
        conditions: RuleCondition(keywords: ['urgent', 'now']),
      );

      engine.addReinforcementRule(rule1);
      final initialCount = engine.ruleCount;
      expect(engine.customRuleCount, equals(1));

      // Add rule with same ID but updated parameters
      engine.addReinforcementRule(rule2);
      expect(engine.ruleCount, equals(initialCount));
      expect(engine.customRuleCount, equals(1));

      final diag = engine.getDiagnostics();
      expect(diag['hasDuplicates'], isFalse);
      expect(diag['customRules'], equals(1));

      // Match should evaluate updated rule2
      final notif = AppNotification(
        id: '4',
        packageName: 'com.app',
        title: 'Notice',
        content: 'urgent now',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final match = engine.match(notif);
      expect(match, isNotNull);
      expect(match!.ruleId, equals(ruleId));
      expect(match.priority, equals('critical'));
    });

    test('sanitizes empty rule IDs and condition keyword strings', () {
      final dirtyRule = NotificationRule(
        id: '   ',
        category: '  finance ',
        priority: ' high ',
        conditions: RuleCondition(
          keywords: ['  money ', '', '   '],
          packages: [' com.bank '],
        ),
      );

      engine.addReinforcementRule(dirtyRule);

      final added = engine.rules.first;
      expect(added.id, startsWith('rlhf-'));
      expect(added.category, equals('finance'));
      expect(added.priority, equals('high'));
      expect(added.conditions.keywords, equals(['money']));
      expect(added.conditions.packages, equals(['com.bank']));
    });

    test('enforces custom rule bounds (max 100 custom rules)', () {
      for (int i = 0; i < 120; i++) {
        engine.addReinforcementRule(
          NotificationRule(
            id: 'rlhf-test-$i',
            category: 'test',
            priority: 'low',
            conditions: RuleCondition(keywords: ['test$i']),
          ),
        );
      }

      expect(engine.customRuleCount, equals(RuleEngine.maxCustomRules));
      final diag = engine.getDiagnostics();
      expect(diag['customRules'], equals(100));
      expect(diag['hasDuplicates'], isFalse);
    });

    test('deduplicates base rules during compile', () {
      const duplicateBaseJson = '''
      {
        "version": "2.0",
        "rules": [
          { "id": "r1", "category": "a", "priority": "low", "conditions": {} },
          { "id": "r1", "category": "b", "priority": "high", "conditions": {} },
          { "id": "r2", "category": "c", "priority": "low", "conditions": {} }
        ]
      }
      ''';

      final testEngine = RuleEngine()..compile(duplicateBaseJson);
      expect(testEngine.ruleCount, equals(2));
      final diag = testEngine.getDiagnostics();
      expect(diag['hasDuplicates'], isFalse);
    });

    test('loadCustomRules prevents duplicate rules even when called repeatedly', () async {
      engine.addReinforcementRule(
        NotificationRule(
          id: 'rlhf-repeat-1',
          category: 'promo',
          priority: 'low',
          conditions: RuleCondition(keywords: ['sale']),
        ),
      );

      final countBefore = engine.ruleCount;

      await engine.loadCustomRules();
      await engine.loadCustomRules();

      expect(engine.ruleCount, equals(countBefore));
      final diag = engine.getDiagnostics();
      expect(diag['hasDuplicates'], isFalse);
    });
  });
}
