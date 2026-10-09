import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/model_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_manager_test_');
    ModelManager.instance.setOverrideDirectory(tempDir);
    await ModelManager.instance.clearDynamicUpdates();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ModelManager Tests', () {
    test('Defaults to static assets when no dynamic models exist', () async {
      await ModelManager.instance.initialize();
      expect(ModelManager.instance.isDynamicUpdateActive, isFalse);
      expect(ModelManager.instance.activeModelVersion, '1.0.0-tflite');

      final lookAgainFile = await ModelManager.instance.getLookAgainModelFile();
      expect(lookAgainFile, isNull);
    });

    test('Computes SHA-256 digest accurately', () {
      final bytes = [1, 2, 3, 4, 5];
      final hash = ModelManager.instance.computeSha256(bytes);
      expect(hash.length, 64);
    });

    test('verifyBundleFile rejects non-existent or empty files', () {
      final nonExistent = File('${tempDir.path}/non_existent.bin');
      expect(ModelManager.instance.verifyBundleFile(nonExistent), isFalse);

      final emptyFile = File('${tempDir.path}/empty.bin');
      emptyFile.writeAsBytesSync([]);
      expect(ModelManager.instance.verifyBundleFile(emptyFile), isFalse);
    });

    test('verifyBundleFile validates matching SHA-256 checksum', () {
      final file = File('${tempDir.path}/test.bin');
      final bytes = [10, 20, 30, 40];
      file.writeAsBytesSync(bytes);

      final expectedHash = ModelManager.instance.computeSha256(bytes);
      expect(ModelManager.instance.verifyBundleFile(file, expectedSha256: expectedHash), isTrue);

      expect(ModelManager.instance.verifyBundleFile(file, expectedSha256: '0000000000000000000000000000000000000000000000000000000000000000'), isFalse);
    });

    test('updateModelBundle applies dynamic update and updates active version', () async {
      final rulesBytes = '{"version": "2.0.0-ota", "rules": []}'.codeUnits;
      final mockModelBytes = List<int>.generate(100, (i) => i);

      final rulesHash = ModelManager.instance.computeSha256(rulesBytes);
      final modelHash = ModelManager.instance.computeSha256(mockModelBytes);

      final manifestJson = '''
      {
        "version": "2.0.0-ota",
        "assets": {
          "rules.json": {"sha256": "$rulesHash"},
          "look_again.tflite": {"sha256": "$modelHash"}
        }
      }
      ''';

      final success = await ModelManager.instance.updateModelBundle(
        {
          'rules.json': rulesBytes,
          'look_again.tflite': mockModelBytes,
        },
        manifestJson: manifestJson,
      );

      expect(success, isTrue);
      expect(ModelManager.instance.isDynamicUpdateActive, isTrue);
      expect(ModelManager.instance.activeModelVersion, '2.0.0-ota');

      final dynamicModel = await ModelManager.instance.getLookAgainModelFile();
      expect(dynamicModel, isNotNull);
      expect(dynamicModel!.existsSync(), isTrue);

      final rulesStr = await ModelManager.instance.getRulesJson();
      expect(rulesStr, contains('2.0.0-ota'));
    });

    test('updateModelBundle fails and rolls back when asset checksum is corrupt', () async {
      final rulesBytes = '{"version": "2.0.0-ota", "rules": []}'.codeUnits;
      final mockModelBytes = List<int>.generate(100, (i) => i);

      final manifestJson = '''
      {
        "version": "2.0.0-ota",
        "assets": {
          "rules.json": {"sha256": "bad_checksum_hash"},
          "look_again.tflite": {"sha256": "another_bad_hash"}
        }
      }
      ''';

      final success = await ModelManager.instance.updateModelBundle(
        {
          'rules.json': rulesBytes,
          'look_again.tflite': mockModelBytes,
        },
        manifestJson: manifestJson,
      );

      expect(success, isFalse);
      expect(ModelManager.instance.isDynamicUpdateActive, isFalse);
    });

    test('clearDynamicUpdates resets manager to static assets', () async {
      final rulesBytes = '{"version": "2.0.0-ota", "rules": []}'.codeUnits;
      await ModelManager.instance.updateModelBundle({'rules.json': rulesBytes});

      expect(ModelManager.instance.isDynamicUpdateActive, isTrue);

      await ModelManager.instance.clearDynamicUpdates();

      expect(ModelManager.instance.isDynamicUpdateActive, isFalse);
      expect(ModelManager.instance.activeModelVersion, '1.0.0-tflite');
    });
  });
}
