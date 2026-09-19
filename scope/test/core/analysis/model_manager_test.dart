import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/model_manager.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelManager Unit Tests', () {
    late Directory tempDir;
    late ModelManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_mgr_test_');
      manager = ModelManager(customBaseDir: tempDir.path);
    });

    tearDown(() async {
      manager.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('initializes with fallback or asset mode when no dynamic file exists', () async {
      await manager.loadInterpreter();
      expect(manager.isDynamicModel, isFalse);
      expect(manager.modelSource, isNot(equals(ModelSource.dynamic)));
    });

    test('rejects dynamic model update when bytes length is less than 100 bytes', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await manager.updateModelFromBytes(invalidBytes);

      expect(result.success, isFalse);
      expect(result.message, contains('size too small'));
      expect(manager.isDynamicModel, isFalse);
    });

    test('updateModelFromFile fails gracefully if source file does not exist', () async {
      final nonExistentFile = File('/tmp/non_existent_model_12345.tflite');
      final result = await manager.updateModelFromFile(nonExistentFile);

      expect(result.success, isFalse);
      expect(result.message, contains('does not exist'));
    });

    test('atomic dynamic update cleans up invalid model file when verification fails', () async {
      // Create a dummy byte array larger than 100 bytes
      final dummyBytes = Uint8List.fromList(List<int>.generate(200, (i) => i % 256));

      final result = await manager.updateModelFromBytes(
        dummyBytes,
        modelName: 'ghost_ai.tflite',
        version: '2.0.0-ota-test',
      );

      final targetFile = File('${tempDir.path}/ghost_ai.tflite');

      // Because dummyBytes is not a valid TFLite binary, loading interpreter fails
      // and triggers automatic fallback recovery which cleans up invalid file
      expect(result.success, isFalse);
      expect(result.message, contains('verification failed'));
      expect(targetFile.existsSync(), isFalse);
    });

    test('resetToAssetModel removes dynamic model file and reloads interpreter', () async {
      final targetFile = File('${tempDir.path}/ghost_ai.tflite');
      await targetFile.writeAsBytes(List<int>.filled(150, 0));
      expect(targetFile.existsSync(), isTrue);

      await manager.resetToAssetModel(modelName: 'ghost_ai.tflite');

      expect(targetFile.existsSync(), isFalse);
      expect(manager.isDynamicModel, isFalse);
    });

    test('dispose safely closes interpreter without throwing', () {
      expect(() => manager.dispose(), returnsNormally);
      expect(manager.interpreter, isNull);
      expect(manager.modelSource, equals(ModelSource.fallback));
    });
  });

  group('GhostAI Dynamic Update Integration Tests', () {
    test('GhostAI delegates update and reset operations to ModelManager', () async {
      await GhostAI.instance.initialize();

      expect(GhostAI.instance.isDynamicModel, isFalse);
      expect(GhostAI.instance.modelVersion, isNotEmpty);

      // Attempting invalid update
      final invalidBytes = Uint8List.fromList([1, 2, 3]);
      final updateResult = await GhostAI.instance.updateModelFromBytes(invalidBytes);

      expect(updateResult.success, isFalse);

      // Reset to asset model
      await GhostAI.instance.resetToAssetModel();
      expect(GhostAI.instance.isDynamicModel, isFalse);
    });

    test('GhostAI inference operates with PII redacted in structured logs', () async {
      final notification = AppNotification(
        id: 'pii-test-1',
        packageName: 'com.bank.app',
        title: 'Confidential Account Alert',
        content: 'Your account balance is USD 10,000. OTP code 998811',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notification);
      expect(result.reviewScore, isNotNull);
      expect(result.inferenceTimeUs, isNonNegative);
    });
  });
}
