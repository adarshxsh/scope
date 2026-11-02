import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_lifecycle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ModelLifecycleManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_lifecycle_test_');
    manager = ModelLifecycleManager.instance;
    manager.setStorageDirectory(tempDir);
  });

  tearDown(() async {
    manager.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelLifecycleManager Manifest & Checksum Validation', () {
    test('ModelManifest correctly parses JSON metadata', () {
      final jsonMap = {
        'model_name': 'ghost_ai',
        'version': '1.2.0',
        'schema_version': '1.0.0',
        'feature_vector_size': 63,
        'sha256': 'abc123def456',
        'input_shape': [1, 63],
        'output_shape': [1, 1],
        'artifacts': {'tflite': 'ghost_ai.tflite'},
      };

      final manifest = ModelManifest.fromJson(jsonMap);
      expect(manifest.modelName, equals('ghost_ai'));
      expect(manifest.version, equals('1.2.0'));
      expect(manifest.schemaVersion, equals('1.0.0'));
      expect(manifest.featureVectorSize, equals(63));
      expect(manifest.sha256, equals('abc123def456'));
      expect(manifest.inputShape, equals([1, 63]));
      expect(manifest.outputShape, equals([1, 1]));
      expect(manifest.artifacts?['tflite'], equals('ghost_ai.tflite'));
    });

    test('verifyChecksum correctly verifies matching SHA256 hash', () {
      final dummyBytes = Uint8List.fromList(utf8.encode('test model binary payload'));
      final expectedHash = sha256.convert(dummyBytes).toString();

      final isValid = manager.verifyChecksum(dummyBytes, expectedHash);
      expect(isValid, isTrue);
    });

    test('verifyChecksum rejects mismatched SHA256 hash', () {
      final dummyBytes = Uint8List.fromList(utf8.encode('corrupted model binary payload'));
      const invalidHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final isValid = manager.verifyChecksum(dummyBytes, invalidHash);
      expect(isValid, isFalse);
    });

    test('verifySchemaDimensions enforces expected input dimension requirements', () {
      const validManifest = ModelManifest(
        modelName: 'ghost_ai',
        version: '1.0.0',
        schemaVersion: '1.0.0',
        featureVectorSize: 63,
        sha256: 'dummy',
        inputShape: [1, 63],
        outputShape: [1, 1],
      );

      const invalidManifest = ModelManifest(
        modelName: 'ghost_ai',
        version: '1.0.0',
        schemaVersion: '1.0.0',
        featureVectorSize: 50,
        sha256: 'dummy',
        inputShape: [1, 50],
        outputShape: [1, 1],
      );

      expect(manager.verifySchemaDimensions(validManifest, expectedInputDim: 63), isTrue);
      expect(manager.verifySchemaDimensions(invalidManifest, expectedInputDim: 63), isFalse);
    });
  });

  group('Model Package Registration & Hot Swap', () {
    test('registerModelPackage rejects model package with invalid SHA256 checksum', () async {
      const manifestJsonStr = '''
      {
        "model_name": "test_model",
        "version": "1.0.0",
        "schema_version": "1.0.0",
        "feature_vector_size": 63,
        "sha256": "bad_hash_value",
        "input_shape": [1, 63],
        "output_shape": [1, 1]
      }
      ''';

      final dummyBytes = Uint8List.fromList(utf8.encode('dummy binary content'));

      final success = await manager.registerModelPackage(
        manifestJsonStr: manifestJsonStr,
        modelBytes: dummyBytes,
        expectedInputDim: 63,
      );

      expect(success, isFalse);
    });

    test('registerModelPackage rejects model package with schema dimension mismatch', () async {
      final dummyBytes = Uint8List.fromList(utf8.encode('dummy binary content'));
      final realHash = sha256.convert(dummyBytes).toString();

      final manifestJsonStr = '''
      {
        "model_name": "test_model",
        "version": "1.0.0",
        "schema_version": "1.0.0",
        "feature_vector_size": 100,
        "sha256": "$realHash",
        "input_shape": [1, 100],
        "output_shape": [1, 1]
      }
      ''';

      final success = await manager.registerModelPackage(
        manifestJsonStr: manifestJsonStr,
        modelBytes: dummyBytes,
        expectedInputDim: 63, // Expected 63, but manifest has 100
      );

      expect(success, isFalse);
    });
  });
}
