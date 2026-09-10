import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/model_manager.dart';
import 'package:scope/database/attention_database.dart';

/// Over-the-air model update and RLHF feedback dataset synchronization service.
class OtaSyncService {
  final http.Client _client;

  OtaSyncService({http.Client? client}) : _client = client ?? http.Client();

  /// Polls server manifest, downloads model bundle, verifies SHA-256 hashes,
  /// and hot-swaps active models if a new version is available.
  Future<bool> checkAndFetchOtaUpdate({
    required String serverManifestUrl,
    LiteRtClassifier? classifier,
  }) async {
    try {
      final response = await _client.get(Uri.parse(serverManifestUrl));
      if (response.statusCode != 200) {
        debugPrint('OtaSyncService: Server returned status ${response.statusCode}');
        return false;
      }

      final manifestJson = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteVersion = manifestJson['version']?.toString() ?? '';
      final currentVersion = ModelManager.instance.activeModelVersion;

      if (remoteVersion.isEmpty || remoteVersion == currentVersion) {
        debugPrint('OtaSyncService: Model up-to-date (current: $currentVersion)');
        return false;
      }

      final filesManifest = manifestJson['files'] as Map<String, dynamic>? ?? {};
      final downloadedFiles = <String, List<int>>{};

      for (final entry in filesManifest.entries) {
        final filename = entry.key;
        final fileMeta = entry.value as Map<String, dynamic>;
        final fileUrl = fileMeta['url']?.toString() ?? '';

        if (fileUrl.isNotEmpty) {
          final fileRes = await _client.get(Uri.parse(fileUrl));
          if (fileRes.statusCode == 200) {
            downloadedFiles[filename] = fileRes.bodyBytes;
          } else {
            debugPrint('OtaSyncService: Failed to download $filename from $fileUrl');
            return false;
          }
        }
      }

      if (downloadedFiles.isEmpty) return false;

      final success = await ModelManager.instance.saveBundle(
        files: downloadedFiles,
        manifestJson: manifestJson,
      );

      if (success) {
        // Hot-swap interpreters in memory
        await GhostAI.instance.initialize(forceReload: true);
        if (classifier != null) {
          await classifier.reload();
        }
        debugPrint('OtaSyncService: Successfully hot-swapped models to version $remoteVersion');
        return true;
      }
    } catch (e) {
      debugPrint('OtaSyncService: OTA update error: $e');
    }
    return false;
  }

  /// Transmits unsynced RLHF feedback samples to remote dataset storage endpoint
  /// and marks synced entries in Drift database.
  Future<int> syncFeedbackEvents({
    required String telemetryEndpoint,
    required AttentionDatabase db,
  }) async {
    try {
      final unsynced = await db.rlhfFeedbackDao.getUnsyncedFeedback();
      if (unsynced.isEmpty) return 0;

      final payload = unsynced.map((e) => {
        'id': e.id,
        'notification_id': e.notificationId,
        'feature_vector': jsonDecode(e.featureVectorJson),
        'feedback_type': e.feedbackType,
        'reward_value': e.rewardValue,
        'original_category': e.originalCategory,
        'original_priority': e.originalPriority,
        'corrected_category': e.correctedCategory,
        'corrected_priority': e.correctedPriority,
        'active_model_version': e.activeModelVersion,
        'timestamp': e.timestamp.toIso8601String(),
      }).toList();

      bool success = false;

      if (telemetryEndpoint.isNotEmpty && telemetryEndpoint != 'mock') {
        final response = await _client.post(
          Uri.parse(telemetryEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'samples': payload}),
        );
        success = response.statusCode == 200 || response.statusCode == 201;
      } else {
        // Mock sync mode
        success = true;
      }

      if (success) {
        final ids = unsynced.map((e) => e.id).toList();
        await db.rlhfFeedbackDao.markAsSynced(ids);
        debugPrint('OtaSyncService: Synced ${ids.length} RLHF feedback events');
        return ids.length;
      }
    } catch (e) {
      debugPrint('OtaSyncService: Telemetry sync error: $e');
    }
    return 0;
  }
}
