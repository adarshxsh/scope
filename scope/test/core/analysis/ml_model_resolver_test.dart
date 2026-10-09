import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ml_model_resolver.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ml_model_resolver_test_');
    GhostAI.instance.resetForTest();
  });

  tearDown(() async {
    GhostAI.instance.resetForTest();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MLModelResolver Unit Tests', () {
    test('resolves active model paths from local app storage when valid file exists', () async {
      final resolver = MLModelResolver(customDirectories: [tempDir]);

      // Create valid mock model.tflite with TFL3 flatbuffer header
      final modelFile = File('${tempDir.path}/model.tflite');
      final validHeader = [28, 0, 0, 0, 0x54, 0x46, 0x4C, 0x33, 1, 2, 3, 4];
      await modelFile.writeAsBytes(validHeader);

      final resolved = await resolver.resolveModelFile('model.tflite');
      expect(resolved, isNotNull);
      expect(resolved!.path, equals(modelFile.path));
    });

    test('rejects empty (0 byte) model files', () async {
      final resolver = MLModelResolver(customDirectories: [tempDir]);

      final emptyFile = File('${tempDir.path}/model.tflite');
      await emptyFile.writeAsBytes([]);

      final resolved = await resolver.resolveModelFile('model.tflite');
      expect(resolved, isNull);
    });

    test('rejects corrupted TFLite model files with invalid header', () async {
      final resolver = MLModelResolver(customDirectories: [tempDir]);

      final badHeaderFile = File('${tempDir.path}/model.tflite');
      final invalidHeader = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      await badHeaderFile.writeAsBytes(invalidHeader);

      final resolved = await resolver.resolveModelFile('model.tflite');
      expect(resolved, isNull);
    });

    test('resolves valid JSON rules file and rejects corrupted JSON', () async {
      final resolver = MLModelResolver(customDirectories: [tempDir]);

      final badJsonFile = File('${tempDir.path}/rules.json');
      await badJsonFile.writeAsString('{ invalid json syntax ...');

      var resolved = await resolver.resolveModelFile('rules.json');
      expect(resolved, isNull);

      final validJson = '{"version": "2.0.0-test", "rules": []}';
      await badJsonFile.writeAsString(validJson);

      resolved = await resolver.resolveModelFile('rules.json');
      expect(resolved, isNotNull);
      expect(await resolved!.readAsString(), equals(validJson));
    });

    test('resolves valid vocab.txt file and rejects empty vocab.txt', () async {
      final resolver = MLModelResolver(customDirectories: [tempDir]);

      final emptyVocab = File('${tempDir.path}/vocab.txt');
      await emptyVocab.writeAsString('   \n  \n');

      var resolved = await resolver.resolveModelFile('vocab.txt');
      expect(resolved, isNull);

      await emptyVocab.writeAsString('[PAD]\n[UNK]\n[CLS]\n[SEP]\ncustomword\n');
      resolved = await resolver.resolveModelFile('vocab.txt');
      expect(resolved, isNotNull);
    });
  });

  group('WordPieceTokenizer Local Vocab Integration', () {
    test('constructs vocabulary from local vocab.txt file when present', () async {
      final vocabFile = File('${tempDir.path}/vocab.txt');
      await vocabFile.writeAsString('[PAD]\n[UNK]\n[CLS]\n[SEP]\ncustomword\nhello\nworld\n');

      final tokenizer = await WordPieceTokenizer.fromFile(vocabFile);
      expect(tokenizer.vocab.containsKey('customword'), isTrue);
      expect(tokenizer.vocab['customword'], equals(4));

      final tokenIds = tokenizer.tokenize('hello customword world');
      expect(tokenIds[0], equals(tokenizer.vocab['[CLS]']));
      expect(tokenIds[1], equals(tokenizer.vocab['hello']));
      expect(tokenIds[2], equals(tokenizer.vocab['customword']));
    });
  });

  group('LiteRtClassifier Local Model & Vocab Resolution', () {
    test('loads tokenizer from local vocab.txt when present', () async {
      final vocabFile = File('${tempDir.path}/vocab.txt');
      await vocabFile.writeAsString('[PAD]\n[UNK]\n[CLS]\n[SEP]\nurgentalert\n');

      final resolver = MLModelResolver(customDirectories: [tempDir]);
      final classifier = LiteRtClassifier(resolver: resolver);

      // Give async initialization time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      final notification = AppNotification(
        id: '1',
        title: 'urgentalert',
        content: 'test content',
        packageName: 'com.test',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notification);
      expect(result.category, isNotNull);
    });
  });

  group('GhostAI Local Model & Fallback Integration', () {
    test('falls back to Interpreter.fromAsset when local model is absent', () async {
      final resolver = MLModelResolver(customDirectories: [tempDir]);

      // No model in tempDir
      await GhostAI.instance.initialize(resolver: resolver);

      // Model attempt finishes (falls back gracefully)
      final notification = AppNotification(
        id: 'notif_1',
        title: 'OTP Verification',
        content: 'Your code is 123456',
        packageName: 'com.whatsapp',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notification);
      expect(result.reviewScore, equals(1.0)); // OTP override / critical rule trigger
    });

    test('loads local rules.json when valid local rules file is present', () async {
      final rulesFile = File('${tempDir.path}/rules.json');
      final testRulesJson = '''
      {
        "version": "9.9.9-dynamic",
        "rules": [
          {
            "id": "custom_test_rule",
            "category": "finance",
            "priority": "critical",
            "conditions": {
              "packages": ["com.custom.bank"],
              "title_keywords": ["specialalert"]
            }
          }
        ]
      }
      ''';
      await rulesFile.writeAsString(testRulesJson);

      final resolver = MLModelResolver(customDirectories: [tempDir]);
      await GhostAI.instance.initialize(resolver: resolver);

      expect(GhostAI.instance.ruleVersion, equals('9.9.9-dynamic'));

      final notification = AppNotification(
        id: 'rule_notif_1',
        title: 'specialalert',
        content: 'Your balance update',
        packageName: 'com.custom.bank',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notification);
      expect(result.ruleScore, equals(1.0));
      expect(result.reviewScore, equals(1.0));
    });

    test('falls back gracefully when local model file is corrupted', () async {
      final corruptedModel = File('${tempDir.path}/model.tflite');
      await corruptedModel.writeAsString('corrupted non-tflite binary data');

      final resolver = MLModelResolver(customDirectories: [tempDir]);

      // Corrupted file rejected by resolver -> falls back to asset
      await GhostAI.instance.initialize(resolver: resolver);

      final notification = AppNotification(
        id: 'corrupted_test_1',
        title: 'Hello',
        content: 'World',
        packageName: 'com.whatsapp',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notification);
      expect(result.reviewScore, isNotNull);
    });
  });

  group('GhostAnalysisEngine Dynamic Rules & Fallback', () {
    test('initializes engine using local rules and resolver', () async {
      final rulesFile = File('${tempDir.path}/rules.json');
      final engineRulesJson = '''
      {
        "version": "8.8.8-engine",
        "rules": [
          {
            "id": "bank_debit",
            "category": "finance",
            "priority": "critical",
            "conditions": {
              "keywords": ["debited"]
            }
          }
        ]
      }
      ''';
      await rulesFile.writeAsString(engineRulesJson);

      final resolver = MLModelResolver(customDirectories: [tempDir]);
      final engine = GhostAnalysisEngine(modelResolver: resolver);

      await engine.initialize();
      expect(engine.ruleEngine.version, equals('8.8.8-engine'));

      final notification = AppNotification(
        id: 'eng_1',
        title: 'Transaction Alert',
        content: 'Your account has been debited Rs. 2,000.',
        packageName: 'com.example.bank',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await engine.analyze(notification);
      expect(result.priority, equals('critical'));
      expect(result.classifiedCategory, equals('finance'));
    });
  });
}
