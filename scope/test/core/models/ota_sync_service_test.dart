import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scope/core/models/model_manager.dart';
import 'package:scope/core/models/ota_sync_service.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  group('OtaSyncService Tests', () {
    late Directory tempDir;
    late AttentionDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ota_sync_test_');
      ModelManager.instance.setCustomDirectory(tempDir);
      await ModelManager.instance.initialize();
      db = AttentionDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
      await ModelManager.instance.clearDynamicModels();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('checkAndFetchOtaUpdate downloads, verifies, and applies new model bundle', () async {
      final modelData = utf8.encode('test model binary payload');
      final modelHash = sha256.convert(modelData).toString();

      final mockManifest = {
        'version': '2.5.0-release',
        'files': {
          'look_again.tflite': {
            'sha256': modelHash,
            'size': modelData.length,
            'url': 'https://models.example.com/look_again.tflite',
          }
        }
      };

      final client = MockClient((request) async {
        if (request.url.toString() == 'https://models.example.com/manifest.json') {
          return http.Response(jsonEncode(mockManifest), 200);
        }
        if (request.url.toString() == 'https://models.example.com/look_again.tflite') {
          return http.Response.bytes(modelData, 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = OtaSyncService(client: client);
      final updated = await service.checkAndFetchOtaUpdate(
        serverManifestUrl: 'https://models.example.com/manifest.json',
      );

      expect(updated, isTrue);
      expect(ModelManager.instance.activeModelVersion, equals('2.5.0-release'));
    });

    test('syncFeedbackEvents uploads unsynced samples and updates DB flags', () async {
      await db.rlhfFeedbackDao.insertFeedback(
        RlhfFeedbackEventsTableCompanion.insert(
          notificationId: const Value('n1'),
          featureVectorJson: '[0.5, 0.2]',
          feedbackType: 'reward',
          rewardValue: const Value(1.0),
          isSynced: const Value(false),
        ),
      );

      final client = MockClient((request) async {
        if (request.url.toString() == 'https://telemetry.example.com/sync') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final samples = body['samples'] as List;
          if (samples.length == 1) {
            return http.Response(jsonEncode({'status': 'ok'}), 200);
          }
        }
        return http.Response('Error', 400);
      });

      final service = OtaSyncService(client: client);
      final count = await service.syncFeedbackEvents(
        telemetryEndpoint: 'https://telemetry.example.com/sync',
        db: db,
      );

      expect(count, equals(1));

      final unsynced = await db.rlhfFeedbackDao.getUnsyncedFeedback();
      expect(unsynced, isEmpty);
    });
  });
}
