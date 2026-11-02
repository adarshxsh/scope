import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/dynamic_model_loader.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dynamic_model_test_');
    DynamicModelLoader.instance.setUpdatesDirectory(tempDir);
    DynamicModelLoader.instance.clearAuditLogs();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DynamicModelLoader Asset Validation Guardrails', () {
    test('validateTfliteBuffer rejects empty or undersized buffers', () {
      final loader = DynamicModelLoader.instance;

      expect(loader.validateTfliteBuffer(null).isValid, isFalse);
      expect(loader.validateTfliteBuffer(Uint8List(0)).isValid, isFalse);
      expect(loader.validateTfliteBuffer(Uint8List(50)).isValid, isFalse);

      final validBuffer = Uint8List(200);
      expect(loader.validateTfliteBuffer(validBuffer).isValid, isTrue);
    });

    test('validateRulesJson enforces JSON structure and rules array', () {
      final loader = DynamicModelLoader.instance;

      expect(loader.validateRulesJson(null).isValid, isFalse);
      expect(loader.validateRulesJson('').isValid, isFalse);
      expect(loader.validateRulesJson('{ invalid json').isValid, isFalse);
      expect(loader.validateRulesJson('{"version": "1.0"}').isValid, isFalse);

      const validJson = '''
      {
        "version": "2.1.0",
        "rules": [
          {
            "id": "rule1",
            "category": "finance",
            "priority": "critical",
            "conditions": {"keywords": ["debit"]}
          }
        ]
      }
      ''';

      final res = loader.validateRulesJson(validJson);
      expect(res.isValid, isTrue);
      expect(res.metadata['version'], equals('2.1.0'));
      expect(res.metadata['ruleCount'], equals(1));
    });

    test('validateVocabString checks for non-empty lines', () {
      final loader = DynamicModelLoader.instance;

      expect(loader.validateVocabString(null).isValid, isFalse);
      expect(loader.validateVocabString('   \n  \n ').isValid, isFalse);

      const validVocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nbank\ncode\n';
      final res = loader.validateVocabString(validVocab);
      expect(res.isValid, isTrue);
      expect(res.metadata['tokenCount'], equals(6));
    });
  });

  group('Dynamic Model Asset Lifecycle & Audit Logging', () {
    test('updateModelAssets writes valid files, creates manifest and logs audit entry', () async {
      final loader = DynamicModelLoader.instance;

      final sampleBytes = Uint8List(256);
      const sampleRules = '{"version": "3.0.0", "rules": []}';
      const sampleVocab = '[PAD]\n[CLS]\nhello\nworld\n';

      final success = await loader.updateModelAssets(
        tfliteBytes: sampleBytes,
        rulesJson: sampleRules,
        vocabText: sampleVocab,
        version: '3.0.0-test',
      );

      expect(success, isTrue);
      expect(loader.currentVersion, equals('3.0.0-test'));

      final loadedRules = await loader.loadRulesJson();
      expect(loadedRules, equals(sampleRules));
      expect(loader.getLoadedSource(ModelAssetType.rules), equals(ModelSourceType.dynamic));

      final loadedVocab = await loader.loadVocabString();
      expect(loadedVocab, equals(sampleVocab));
      expect(loader.getLoadedSource(ModelAssetType.vocab), equals(ModelSourceType.dynamic));

      final auditLogs = loader.getAuditLogs();
      expect(auditLogs, isNotEmpty);
      expect(auditLogs.any((l) => l.eventType == 'UPDATE_SUCCESS'), isTrue);
      expect(auditLogs.any((l) => l.eventType == 'LOAD_DYNAMIC'), isTrue);
    });

    test('invalid dynamic updates are rejected and leave existing files intact', () async {
      final loader = DynamicModelLoader.instance;

      final success = await loader.updateModelAssets(
        tfliteBytes: Uint8List(10), // Too small
        version: 'invalid-ver',
      );

      expect(success, isFalse);

      final auditLogs = loader.getAuditLogs();
      expect(auditLogs.any((l) => l.eventType == 'UPDATE_FAILED'), isTrue);
    });

    test('clearDynamicUpdates removes files and restores default source states', () async {
      final loader = DynamicModelLoader.instance;

      await loader.updateModelAssets(
        rulesJson: '{"version": "4.0.0", "rules": []}',
        version: '4.0.0-temp',
      );

      expect(await loader.loadRulesJson(), isNotNull);

      await loader.clearDynamicUpdates();

      final auditLogs = loader.getAuditLogs();
      expect(auditLogs.any((l) => l.eventType == 'CLEAR_UPDATES'), isTrue);
    });
  });

  group('GhostAI Integration with Dynamic Loader', () {
    test('GhostAI prediction uses dynamic model rules and maintains privacy guardrails', () async {
      final loader = DynamicModelLoader.instance;

      const dynamicRules = '''
      {
        "version": "9.9.9",
        "rules": [
          {
            "id": "custom_test_rule",
            "category": "scholarship",
            "priority": "critical",
            "conditions": {
              "title_keywords": ["grant_alert_special"]
            }
          }
        ]
      }
      ''';

      await loader.updateModelAssets(
        rulesJson: dynamicRules,
        version: '9.9.9-test',
      );

      await GhostAI.instance.reload();

      final notif = AppNotification(
        id: 'test_123',
        packageName: 'com.example.app',
        title: 'grant_alert_special notification',
        content: 'Your grant application was processed',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);

      expect(result.reviewScore, equals(1.0)); // Critical priority from dynamic rule
      expect(GhostAI.instance.ruleVersion, equals('9.9.9'));

      // Ensure audit logs contain no sensitive user PII
      final auditLogs = loader.getAuditLogs();
      for (final log in auditLogs) {
        expect(log.details.contains('grant_alert_special'), isFalse);
        expect(log.details.contains('Your grant application'), isFalse);
      }
    });
  });
}
