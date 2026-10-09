import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/model_manager.dart';

void main() {
  group('ModelManager Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_manager_test_');
      ModelManager.instance.setCustomDirectory(tempDir);
      await ModelManager.instance.initialize();
    });

    tearDown(() async {
      await ModelManager.instance.clearDynamicModels();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Initial state falls back to bundled asset defaults', () {
      expect(ModelManager.instance.activeModelVersion, equals('1.0.0-bundled'));
    });

    test('saveBundle rejects bundle if SHA-256 hash mismatch', () async {
      final fakeModelBytes = utf8.encode('dummy model bytes');
      final corruptedHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final manifest = {
        'version': '2.0.0-ota',
        'files': {
          'look_again.tflite': {
            'sha256': corruptedHash,
            'size': fakeModelBytes.length,
          }
        }
      };

      final success = await ModelManager.instance.saveBundle(
        files: {'look_again.tflite': fakeModelBytes},
        manifestJson: manifest,
      );

      expect(success, isFalse);
      expect(ModelManager.instance.activeModelVersion, equals('1.0.0-bundled'));
    });

    test('saveBundle accepts and persists valid bundle with matching SHA-256 hash', () async {
      final fakeModelBytes = utf8.encode('valid tflite model content');
      final validHash = sha256.convert(fakeModelBytes).toString();

      final manifest = {
        'version': '2.1.0-ota',
        'files': {
          'look_again.tflite': {
            'sha256': validHash,
            'size': fakeModelBytes.length,
          }
        }
      };

      final success = await ModelManager.instance.saveBundle(
        files: {'look_again.tflite': fakeModelBytes},
        manifestJson: manifest,
      );

      expect(success, isTrue);
      expect(ModelManager.instance.activeModelVersion, equals('2.1.0-ota'));

      final localFile = await ModelManager.instance.getLocalModelFile('look_again.tflite');
      expect(localFile, isNotNull);
      expect(await localFile!.readAsString(), equals('valid tflite model content'));
    });
  });
}
