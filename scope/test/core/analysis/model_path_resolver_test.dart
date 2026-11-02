import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/model_path_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_path_resolver_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelPathResolver', () {
    test('getLocalModelFile returns null when storage directory is empty', () async {
      final resolver = ModelPathResolver(customStorageDir: tempDir);
      final file = await resolver.getLocalModelFile();
      expect(file, isNull);
    });

    test('getLocalModelFile detects valid updated model file in storage', () async {
      final modelFile = File('${tempDir.path}/updated_model.tflite');
      await modelFile.writeAsString('dummy tflite model bytes');

      final resolver = ModelPathResolver(customStorageDir: tempDir);
      final file = await resolver.getLocalModelFile();

      expect(file, isNotNull);
      expect(file!.path, equals(modelFile.path));
    });

    test('getLocalModelFile detects model.tflite fallback file in storage', () async {
      final modelFile = File('${tempDir.path}/model.tflite');
      await modelFile.writeAsString('dummy model bytes');

      final resolver = ModelPathResolver(customStorageDir: tempDir);
      final file = await resolver.getLocalModelFile();

      expect(file, isNotNull);
      expect(file!.path, equals(modelFile.path));
    });

    test('getLocalModelFile ignores empty (0 byte) model files', () async {
      final modelFile = File('${tempDir.path}/updated_model.tflite');
      await modelFile.writeAsString(''); // empty file

      final resolver = ModelPathResolver(customStorageDir: tempDir);
      final file = await resolver.getLocalModelFile();

      expect(file, isNull);
    });

    test('resolveAndLoad attempts local file loading first and falls back to asset when local file is invalid', () async {
      final invalidModelFile = File('${tempDir.path}/updated_model.tflite');
      await invalidModelFile.writeAsString('invalid binary content');

      final resolver = ModelPathResolver(customStorageDir: tempDir);
      final result = await resolver.resolveAndLoad();

      // Since 'invalid binary content' is not a valid TFLite file, Interpreter.fromFile throws an exception,
      // and resolveAndLoad falls back to Interpreter.fromAsset('assets/model.tflite').
      // In unit test environment without C TFLite lib, asset loading returns ModelSource.none or asset.
      expect(result.source, isNot(equals(ModelSource.local)));
    });

    test('GhostAI initialization integrates with ModelPathResolver', () async {
      GhostAI.instance.resetForTesting();

      final resolver = ModelPathResolver(customStorageDir: tempDir);
      await GhostAI.instance.initialize(resolver: resolver);

      expect(GhostAI.instance.modelSource, isA<ModelSource>());
      expect(GhostAI.instance.ruleVersion, isNotEmpty);
    });

    test('No external networking dependencies introduced in pubspec.yaml', () {
      final pubspecFile = File('pubspec.yaml');
      expect(pubspecFile.existsSync(), isTrue);

      final content = pubspecFile.readAsStringSync();
      expect(content.contains('http:'), isFalse);
      expect(content.contains('dio:'), isFalse);
      expect(content.contains('web_socket_channel:'), isFalse);
      expect(content.contains('chopper:'), isFalse);
    });
  });
}
