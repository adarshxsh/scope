import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/storage/backup_exclusion_helper.dart';
import 'package:scope/core/storage/storage_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocsDir;
  late Directory tempSupportDir;

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('docs_dir_test_');
    tempSupportDir = await Directory.systemTemp.createTemp('support_dir_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDocsDir.path;
        }
        if (methodCall.method == 'getApplicationSupportDirectory') {
          return tempSupportDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
    if (await tempSupportDir.exists()) {
      await tempSupportDir.delete(recursive: true);
    }
  });

  group('StorageMigrator & BackupExclusionHelper Tests', () {
    test('getAppSupportDirectory creates support directory', () async {
      final dir = await StorageMigrator.getAppSupportDirectory();
      expect(await dir.exists(), isTrue);
      expect(dir.path, equals(tempSupportDir.path));
    });

    test('migrateLegacyFiles moves legacy files from Documents to Support directory', () async {
      // Create legacy files in Documents directory
      final legacyDb = File('${tempDocsDir.path}/attention_os.db');
      await legacyDb.writeAsString('mock sqlite data');

      final legacyRules = File('${tempDocsDir.path}/rlhf_rules.json');
      await legacyRules.writeAsString('[{"id": "rlhf-1", "category": "msg", "priority": "high", "conditions": {}}]');

      expect(await legacyDb.exists(), isTrue);
      expect(await legacyRules.exists(), isTrue);

      // Run migration
      await StorageMigrator.migrateLegacyFiles();

      // Legacy files should be removed from Documents directory
      expect(await legacyDb.exists(), isFalse);
      expect(await legacyRules.exists(), isFalse);

      // Migrated files should exist in Application Support directory
      final migratedDb = File('${tempSupportDir.path}/attention_os.db');
      final migratedRules = File('${tempSupportDir.path}/rlhf_rules.json');

      expect(await migratedDb.exists(), isTrue);
      expect(await migratedRules.exists(), isTrue);
      expect(await migratedDb.readAsString(), equals('mock sqlite data'));
      expect(await migratedRules.readAsString(), contains('rlhf-1'));
    });

    test('BackupExclusionHelper runs gracefully for existing files', () async {
      final testFile = File('${tempSupportDir.path}/test_exclusion.txt');
      await testFile.writeAsString('test content');

      final result = await BackupExclusionHelper.excludeFromBackup(testFile.path);
      // Non-iOS platform in test environment should return true without errors
      expect(result, isTrue);
    });

    test('RuleEngine saves and loads rlhf_rules.json in Application Support directory', () async {
      final engine = RuleEngine();
      engine.compile('{"version": "1.0", "rules": []}');

      final customRule = NotificationRule(
        id: 'rlhf-custom-1',
        category: 'msg',
        priority: 'high',
        conditions: const RuleCondition(keywords: ['urgent']),
      );

      await engine.addReinforcementRule(customRule);

      // File should now exist in Support directory
      final supportRulesFile = File('${tempSupportDir.path}/rlhf_rules.json');
      expect(await supportRulesFile.exists(), isTrue);
      final content = await supportRulesFile.readAsString();
      expect(content, contains('rlhf-custom-1'));

      // New RuleEngine instance loading rules
      final engine2 = RuleEngine();
      engine2.compile('{"version": "1.0", "rules": []}');
      await engine2.loadCustomRules();

      final notification = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Notice',
        content: 'Very urgent message',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final match = engine2.match(notification);
      expect(match, isNotNull);
      expect(match!.ruleId, equals('rlhf-custom-1'));
    });
  });
}
