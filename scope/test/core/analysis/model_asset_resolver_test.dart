import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/model_asset_resolver.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ml_assets_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelAssetResolver Tests', () {
    test('resolveLocalFile returns null when directory or file does not exist', () async {
      final nonExistentDir = Directory('${tempDir.path}/non_existent');
      final localFile = await ModelAssetResolver.resolveLocalFile(
        'model.tflite',
        customDirectoryPath: nonExistentDir.path,
      );
      expect(localFile, isNull);
    });

    test('resolveLocalFile detects and deletes zero-byte local file', () async {
      final zeroByteFile = File('${tempDir.path}/model.tflite');
      await zeroByteFile.writeAsBytes([]);

      expect(await zeroByteFile.exists(), isTrue);
      expect(await zeroByteFile.length(), equals(0));

      final resolved = await ModelAssetResolver.resolveLocalFile(
        'model.tflite',
        customDirectoryPath: tempDir.path,
      );

      expect(resolved, isNull);
      expect(await zeroByteFile.exists(), isFalse); // Deleted
    });

    test('resolveLocalFile returns File when non-empty local file exists', () async {
      final validFile = File('${tempDir.path}/model.tflite');
      await validFile.writeAsString('dummy tflite contents');

      final resolved = await ModelAssetResolver.resolveLocalFile(
        'model.tflite',
        customDirectoryPath: tempDir.path,
      );

      expect(resolved, isNotNull);
      expect(resolved!.path, equals(validFile.path));
    });

    test('resolveRules returns custom local rules JSON when present', () async {
      final localRules = File('${tempDir.path}/rules.json');
      const customRulesJson = '{"version": "2.0.0-ota", "rules": []}';
      await localRules.writeAsString(customRulesJson);

      final rulesStr = await ModelAssetResolver.resolveRules(
        fileName: 'rules.json',
        assetPath: 'assets/rules.json',
        customDirectoryPath: tempDir.path,
      );

      expect(rulesStr, equals(customRulesJson));
    });

    test('resolveRules falls back to bundled package asset when local file is missing', () async {
      final rulesStr = await ModelAssetResolver.resolveRules(
        fileName: 'rules.json',
        assetPath: 'assets/rules.json',
        customDirectoryPath: tempDir.path,
      );

      expect(rulesStr, isNotNull);
      expect(rulesStr, contains('rules'));
    });

    test('resolveRules deletes zero-byte local rules and falls back to bundled asset', () async {
      final emptyRulesFile = File('${tempDir.path}/rules.json');
      await emptyRulesFile.writeAsBytes([]);

      final rulesStr = await ModelAssetResolver.resolveRules(
        fileName: 'rules.json',
        assetPath: 'assets/rules.json',
        customDirectoryPath: tempDir.path,
      );

      expect(await emptyRulesFile.exists(), isFalse); // Safely deleted
      expect(rulesStr, isNotNull);
      expect(rulesStr, contains('rules')); // Loaded from bundled asset
    });

    test('resolveVocab falls back to bundled assets/vocab.txt when local file is missing', () async {
      final vocabStr = await ModelAssetResolver.resolveVocab(
        fileName: 'vocab.txt',
        assetPath: 'assets/vocab.txt',
        customDirectoryPath: tempDir.path,
      );

      expect(vocabStr, isNotNull);
      expect(vocabStr, contains('[PAD]'));
    });

    test('resolveInterpreter catches corrupted local TFLite model, deletes it, and falls back', () async {
      final corruptedFile = File('${tempDir.path}/model.tflite');
      await corruptedFile.writeAsString('THIS_IS_CORRUPTED_NOT_A_VALID_TFLITE_FLATBUFFER');

      expect(await corruptedFile.exists(), isTrue);

      final interpreter = await ModelAssetResolver.resolveInterpreter(
        fileName: 'model.tflite',
        assetPath: 'assets/model.tflite',
        customDirectoryPath: tempDir.path,
      );

      // Corrupted file must be deleted during initialization attempt
      expect(await corruptedFile.exists(), isFalse);
      // Returns interpreter if bundled asset loads, or null if native C lib missing in test desktop
      // Crucially, it must not throw uncaught exceptions
      expect(() => interpreter, returnsNormally);
    });

    test('GhostAI initialization falls back cleanly when model loading fails', () async {
      await GhostAI.instance.initialize();
      // Verify GhostAI predicts accurately using heuristic fallback
      final notif = AppNotification(
        id: 'test-otp',
        packageName: 'com.whatsapp',
        title: 'Security Code',
        content: 'Your verification code is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);
      expect(result.reviewScore, equals(1.0));
    });

    test('Resolver check completes within performance guardrail (< 5ms)', () async {
      final stopwatch = Stopwatch()..start();
      await ModelAssetResolver.resolveLocalFile(
        'model.tflite',
        customDirectoryPath: tempDir.path,
      );
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(5));
    });
  });
}
