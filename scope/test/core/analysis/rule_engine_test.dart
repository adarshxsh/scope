import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('rule_engine_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
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

    test('evaluates base system rules prior to custom rules (tiered execution precedence)', () {
      // Add a custom rule that matches WhatsApp Mom but tries to categorize it as 'promo'
      final customRule = NotificationRule(
        id: 'rlhf-override',
        category: 'promo',
        priority: 'high',
        conditions: const RuleCondition(
          packages: ['com.whatsapp'],
          titleKeywords: ['Mom'],
        ),
      );

      final added = engine.addReinforcementRule(customRule);
      expect(added, isTrue);

      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Call me back.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = engine.match(notif);
      expect(result, isNotNull);
      // Base rule 'whatsapp_mom' must match first and take precedence over custom rule
      expect(result!.ruleId, equals('whatsapp_mom'));
      expect(result.isCustom, isFalse);
    });

    test('addReinforcementRule clamps critical priority to high and rejects reserved system IDs', () {
      final reservedRule = NotificationRule(
        id: 'otp_security',
        category: 'sys',
        priority: 'critical',
        conditions: const RuleCondition(keywords: ['otp']),
      );

      expect(engine.addReinforcementRule(reservedRule), isFalse);

      final customRule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'finance',
        priority: 'critical',
        conditions: const RuleCondition(keywords: ['paytm']),
      );

      expect(engine.addReinforcementRule(customRule), isTrue);
      expect(engine.customRules.length, equals(1));
      expect(engine.customRules.first.priority, equals('high'));
      expect(engine.customRules.first.id, equals('rlhf-custom-1'));
    });

    test('enforces capacity limit of 50 custom rules', () {
      for (int i = 0; i < 50; i++) {
        final rule = NotificationRule(
          id: 'rlhf-rule-$i',
          category: 'test',
          priority: 'high',
          conditions: RuleCondition(keywords: ['test-$i']),
        );
        expect(engine.addReinforcementRule(rule), isTrue);
      }

      expect(engine.customRules.length, equals(50));

      // 51st rule should be rejected due to capacity limit
      final overflowRule = NotificationRule(
        id: 'rlhf-rule-50',
        category: 'test',
        priority: 'high',
        conditions: const RuleCondition(keywords: ['overflow']),
      );

      expect(engine.addReinforcementRule(overflowRule), isFalse);
      expect(engine.customRules.length, equals(50));
    });

    test('loadCustomRules safely handles corrupted JSON payloads without crashing', () async {
      final rlhfFile = File('${tempDir.path}/rlhf_rules.json');
      await rlhfFile.writeAsString('{ corrupted json payload ::: ');

      await engine.loadCustomRules();
      expect(engine.customRules, isEmpty);

      // Verify file was rewritten with sanitized content
      final content = await rlhfFile.readAsString();
      expect(content, equals('[]'));
    });

    test('loadCustomRules filters malformed rule objects and enforces capacity cap', () async {
      final rlhfFile = File('${tempDir.path}/rlhf_rules.json');
      final rawData = [
        {'id': 'otp_security', 'priority': 'critical', 'conditions': {'keywords': ['otp']}}, // Reserved ID -> discard
        {'id': 'rlhf-valid', 'priority': 'critical', 'conditions': {'keywords': ['valid']}}, // Critical -> clamp to high
        {'invalid_field': 123}, // Malformed -> discard
      ];
      await rlhfFile.writeAsString(json.encode(rawData));

      await engine.loadCustomRules();
      expect(engine.customRules.length, equals(1));
      expect(engine.customRules.first.id, equals('rlhf-valid'));
      expect(engine.customRules.first.priority, equals('high'));
    });
  });
}
