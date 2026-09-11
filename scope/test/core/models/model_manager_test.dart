import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/model_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ModelManager modelManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_manager_test_');
    modelManager = ModelManager(customDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('calculateSha256 and verifyChecksum correctly validate file integrity', () async {
    final file = File(p.join(tempDir.path, 'test_model.tflite'));
    final content = utf8.encode('dummy tflite model content');
    await file.writeAsBytes(content);

    final expectedHash = sha256.convert(content).toString();
    final calculatedHash = await modelManager.calculateSha256(file);
    expect(calculatedHash, equals(expectedHash));

    final isValid = await modelManager.verifyChecksum(file, expectedHash);
    expect(isValid, isTrue);

    final isInvalid = await modelManager.verifyChecksum(file, 'wronghash123');
    expect(isInvalid, isFalse);
  });

  test('saveDynamicModel writes file, verifies checksum, and saves model_manifest.json', () async {
    final bytes = utf8.encode('sample model bytes');
    final hash = sha256.convert(bytes).toString();

    final manifestData = {
      'version': '2.0.0',
      'sha256': hash,
      'target_engine': 'GhostAI',
    };

    final file = await modelManager.saveDynamicModel(
      'look_again.tflite',
      bytes,
      expectedChecksum: hash,
      manifest: manifestData,
    );

    expect(await file.exists(), isTrue);
    final manifest = await modelManager.loadManifest();
    expect(manifest, isNotNull);
    expect(manifest!['version'], equals('2.0.0'));
    expect(manifest['sha256'], equals(hash));
  });

  test('resolveDynamicModel returns file if valid and checksum matches manifest', () async {
    final bytes = utf8.encode('valid model binary');
    final hash = sha256.convert(bytes).toString();

    final manifestFile = File(p.join(tempDir.path, 'model_manifest.json'));
    await manifestFile.writeAsString(jsonEncode({
      'version': '1.0.0',
      'sha256': hash,
    }));

    final modelFile = File(p.join(tempDir.path, 'look_again.tflite'));
    await modelFile.writeAsBytes(bytes);

    final resolved = await modelManager.getLookAgainModelFile();
    expect(resolved, isNotNull);
    expect(resolved!.path, equals(modelFile.path));
  });

  test('resolveDynamicModel rejects corrupt or checksum mismatched files', () async {
    final manifestFile = File(p.join(tempDir.path, 'model_manifest.json'));
    await manifestFile.writeAsString(jsonEncode({
      'version': '1.0.0',
      'sha256': '0000000000000000000000000000000000000000000000000000000000000000',
    }));

    final modelFile = File(p.join(tempDir.path, 'look_again.tflite'));
    await modelFile.writeAsBytes(utf8.encode('corrupted bytes'));

    final resolved = await modelManager.getLookAgainModelFile();
    expect(resolved, isNull);
  });

  test('resolveDynamicModel ignores empty 0-byte files', () async {
    final modelFile = File(p.join(tempDir.path, 'text_classifier.tflite'));
    await modelFile.writeAsBytes([]);

    final resolved = await modelManager.getCategoryModelFile();
    expect(resolved, isNull);
  });
}
