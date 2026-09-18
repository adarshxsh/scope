import 'package:flutter/foundation.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/model_manager.dart';

/// Handles dynamic Over-The-Air (OTA) ML model update synchronization,
/// verification guardrails, and isolated runtime re-initialization.
class OtaSyncService {
  final ModelManager _modelManager;

  OtaSyncService({ModelManager? modelManager})
      : _modelManager = modelManager ?? ModelManager.instance;

  /// Returns whether a dynamic ML update is currently applied.
  bool get isDynamicUpdateActive => _modelManager.isDynamicUpdateActive;

  /// Returns the current active model version string.
  String get activeModelVersion => _modelManager.activeModelVersion;

  /// Ingests, verifies, and applies a dynamic ML update bundle.
  /// On successful verification, triggers runtime reloads of AI classification components.
  Future<bool> syncModelBundle(
    Map<String, List<int>> bundleFiles, {
    String? manifestJson,
    GhostAI? ghostAi,
    LiteRtClassifier? classifier,
  }) async {
    try {
      final success = await _modelManager.updateModelBundle(
        bundleFiles,
        manifestJson: manifestJson,
      );

      if (!success) {
        debugPrint('OtaSyncService: Bundle verification or application failed.');
        return false;
      }

      // Reload runtime components safely with isolated exception handling
      try {
        final ai = ghostAi ?? GhostAI.instance;
        await ai.reload();
      } catch (e) {
        debugPrint('OtaSyncService: Error reloading GhostAI after update: $e');
      }

      try {
        final lc = classifier ?? LiteRtClassifier();
        await lc.reload();
      } catch (e) {
        debugPrint('OtaSyncService: Error reloading LiteRtClassifier after update: $e');
      }

      return true;
    } catch (e) {
      debugPrint('OtaSyncService: Isolated exception during syncModelBundle: $e');
      return false;
    }
  }

  /// Rollbacks any applied dynamic updates and restores static bundled asset baseline.
  Future<void> rollbackToStaticAssets({
    GhostAI? ghostAi,
    LiteRtClassifier? classifier,
  }) async {
    try {
      await _modelManager.clearDynamicUpdates();
      final ai = ghostAi ?? GhostAI.instance;
      await ai.reload();

      final lc = classifier ?? LiteRtClassifier();
      await lc.reload();
    } catch (e) {
      debugPrint('OtaSyncService: Exception during rollbackToStaticAssets: $e');
    }
  }
}
