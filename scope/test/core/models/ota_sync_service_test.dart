import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/model_manager.dart';
import 'package:scope/core/models/ota_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OtaSyncService otaService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ota_sync_test_');
    ModelManager.instance.setOverrideDirectory(tempDir);
    await ModelManager.instance.clearDynamicUpdates();
    otaService = OtaSyncService();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('OtaSyncService Tests', () {
    test('syncModelBundle successfully applies valid model bundle', () async {
      final rulesBytes = '{"version": "2.1.0-ota", "rules": []}'.codeUnits;
      final mockModelBytes = List<int>.generate(64, (i) => i);

      final rulesHash = ModelManager.instance.computeSha256(rulesBytes);
      final modelHash = ModelManager.instance.computeSha256(mockModelBytes);

      final manifestJson = '''
      {
        "version": "2.1.0-ota",
        "assets": {
          "rules.json": {"sha256": "$rulesHash"},
          "look_again.tflite": {"sha256": "$modelHash"}
        }
      }
      ''';

      final success = await otaService.syncModelBundle(
        {
          'rules.json': rulesBytes,
          'look_again.tflite': mockModelBytes,
        },
        manifestJson: manifestJson,
      );

      expect(success, isTrue);
      expect(otaService.isDynamicUpdateActive, isTrue);
      expect(otaService.activeModelVersion, '2.1.0-ota');
    });

    test('syncModelBundle rejects corrupt bundle and preserves static mode', () async {
      final rulesBytes = '{"version": "2.1.0-ota", "rules": []}'.codeUnits;

      final manifestJson = '''
      {
        "version": "2.1.0-ota",
        "assets": {
          "rules.json": {"sha256": "invalid_hash_value"}
        }
      }
      ''';

      final success = await otaService.syncModelBundle(
        {'rules.json': rulesBytes},
        manifestJson: manifestJson,
      );

      expect(success, isFalse);
      expect(otaService.isDynamicUpdateActive, isFalse);
    });

    test('rollbackToStaticAssets resets model resolution', () async {
      final rulesBytes = '{"version": "2.1.0-ota", "rules": []}'.codeUnits;
      await otaService.syncModelBundle({'rules.json': rulesBytes});

      expect(otaService.isDynamicUpdateActive, isTrue);

      await otaService.rollbackToStaticAssets();

      expect(otaService.isDynamicUpdateActive, isFalse);
      expect(otaService.activeModelVersion, '1.0.0-tflite');
    });
  });
}
