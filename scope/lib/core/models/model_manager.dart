import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages on-device dynamic TFLite model lifecycle, checksum verification,
/// manifest loading, and fallback resolution.
class ModelManager {
  static ModelManager? _instance;
  Directory? _customDirectory;

  ModelManager({Directory? customDirectory}) : _customDirectory = customDirectory;

  static ModelManager get instance => _instance ??= ModelManager();

  /// Gets the working directory for dynamic model storage.
  Future<Directory> getStorageDirectory() async {
    if (_customDirectory != null) {
      return _customDirectory!;
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Calculates SHA-256 checksum of a local file.
  Future<String> calculateSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Verifies file SHA-256 checksum against expected hash.
  Future<bool> verifyChecksum(File file, String expectedChecksum) async {
    if (!await file.exists()) return false;
    final actualChecksum = await calculateSha256(file);
    return actualChecksum.toLowerCase() == expectedChecksum.toLowerCase();
  }

  /// Loads dynamic model manifest metadata if present.
  Future<Map<String, dynamic>?> loadManifest([String manifestName = 'model_manifest.json']) async {
    try {
      final dir = await getStorageDirectory();
      var file = File(p.join(dir.path, manifestName));
      if (!await file.exists()) {
        file = File(p.join(dir.path, 'manifest.json'));
      }
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ModelManager: Error reading model manifest: $e');
      return null;
    }
  }

  /// Resolves the Look-Again priority regression model file from local storage.
  /// Returns null if dynamic file is missing, empty, or fails checksum verification.
  Future<File?> getLookAgainModelFile() async {
    return await resolveDynamicModel(
      candidateNames: ['look_again.tflite', 'model.tflite'],
    );
  }

  /// Resolves the LiteRT category classification model file from local storage.
  /// Returns null if dynamic file is missing, empty, or fails checksum verification.
  Future<File?> getCategoryModelFile() async {
    return await resolveDynamicModel(
      candidateNames: ['text_classifier.tflite', 'category_model.tflite'],
    );
  }

  /// Resolves a dynamic model file by candidate names, validating non-empty content
  /// and SHA-256 checksum against model manifest if available.
  Future<File?> resolveDynamicModel({required List<String> candidateNames}) async {
    try {
      final dir = await getStorageDirectory();
      final manifest = await loadManifest();

      for (final name in candidateNames) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) {
          final length = await file.length();
          if (length == 0) {
            debugPrint('ModelManager: Dynamic model file $name is empty. Skipping.');
            continue;
          }

          // If manifest contains checksum for this file or model, verify it
          final expectedChecksum = _extractExpectedChecksum(manifest, name);
          if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
            final isValid = await verifyChecksum(file, expectedChecksum);
            if (!isValid) {
              debugPrint('ModelManager: Checksum mismatch for dynamic model $name. Skipping.');
              continue;
            }
          }

          debugPrint('ModelManager: Successfully resolved dynamic model file $name');
          return file;
        }
      }
    } catch (e) {
      debugPrint('ModelManager: Error resolving dynamic model: $e');
    }
    return null;
  }

  /// Saves a dynamic model binary to local storage after SHA-256 verification,
  /// optionally writing manifest metadata.
  Future<File> saveDynamicModel(
    String filename,
    List<int> bytes, {
    String? expectedChecksum,
    Map<String, dynamic>? manifest,
  }) async {
    final dir = await getStorageDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);

    if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
      final isValid = await verifyChecksum(file, expectedChecksum);
      if (!isValid) {
        await file.delete();
        throw FormatException('Checksum verification failed for $filename');
      }
    }

    if (manifest != null) {
      final manifestFile = File(p.join(dir.path, 'model_manifest.json'));
      await manifestFile.writeAsString(jsonEncode(manifest), flush: true);
    }

    return file;
  }

  String? _extractExpectedChecksum(Map<String, dynamic>? manifest, String filename) {
    if (manifest == null) return null;
    if (manifest.containsKey('sha256')) {
      return manifest['sha256'] as String?;
    }
    if (manifest.containsKey('checksum')) {
      return manifest['checksum'] as String?;
    }
    if (manifest.containsKey('models') && manifest['models'] is Map) {
      final models = manifest['models'] as Map<String, dynamic>;
      if (models.containsKey(filename) && models[filename] is Map) {
        return models[filename]['sha256'] as String?;
      }
    }
    return null;
  }
}
