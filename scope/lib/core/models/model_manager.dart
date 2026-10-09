import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Central model resolution manager enforcing verification boundaries,
/// integrity checks, and isolated fallback to static assets.
class ModelManager {
  static ModelManager? _instance;
  Directory? _overrideDirectory;

  String _activeVersion = '1.0.0-tflite';
  bool _isDynamicActive = false;

  ModelManager._();

  static ModelManager get instance => _instance ??= ModelManager._();

  /// Visible for testing: override base storage directory.
  void setOverrideDirectory(Directory? directory) {
    _overrideDirectory = directory;
  }

  /// Active version of the classification model pipeline.
  String get activeModelVersion => _activeVersion;

  /// Whether a dynamic OTA ML model update is currently verified and active.
  bool get isDynamicUpdateActive => _isDynamicActive;

  /// Resolves the local dynamic model directory.
  Future<Directory> get dynamicModelDirectory async {
    if (_overrideDirectory != null) {
      final dir = Directory('${_overrideDirectory!.path}/models/ota');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }

    try {
      final baseDir = await getApplicationSupportDirectory();
      final dir = Directory('${baseDir.path}/models/ota');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      final baseDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${baseDir.path}/models/ota');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }
  }

  /// Initializes the ModelManager and checks for existing dynamic updates.
  Future<void> initialize() async {
    try {
      final otaDir = await dynamicModelDirectory;
      final isValid = await verifyDirectory(otaDir);
      if (isValid) {
        _isDynamicActive = true;
        _activeVersion = await _resolveManifestVersion(otaDir);
        debugPrint('ModelManager: Verified dynamic ML model update active (version: $_activeVersion).');
      } else {
        _isDynamicActive = false;
        _activeVersion = '1.0.0-tflite';
        debugPrint('ModelManager: Dynamic ML updates unverified or missing. Falling back to static assets.');
      }
    } catch (e) {
      _isDynamicActive = false;
      _activeVersion = '1.0.0-tflite';
      debugPrint('ModelManager: Failed during initialization check: $e. Using static assets.');
    }
  }

  /// Computes SHA-256 digest hex string for the given file bytes.
  String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Verifies a single file against size constraints and optional expected SHA-256.
  bool verifyBundleFile(File file, {String? expectedSha256}) {
    try {
      if (!file.existsSync()) return false;
      final length = file.lengthSync();
      if (length <= 0) return false;

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final bytes = file.readAsBytesSync();
        final actualSha256 = computeSha256(bytes);
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          debugPrint('ModelManager: SHA-256 mismatch for ${file.path}. Expected $expectedSha256, got $actualSha256');
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('ModelManager: File verification exception for ${file.path}: $e');
      return false;
    }
  }

  /// Verifies the completeness and integrity of a dynamic model directory.
  Future<bool> verifyDirectory(Directory otaDir) async {
    try {
      if (!otaDir.existsSync()) return false;

      final manifestFile = File('${otaDir.path}/manifest.json');
      if (manifestFile.existsSync() && manifestFile.lengthSync() > 0) {
        try {
          final content = manifestFile.readAsStringSync();
          final manifest = json.decode(content) as Map<String, dynamic>;
          final assets = manifest['assets'] as Map<String, dynamic>?;

          if (assets != null) {
            for (final entry in assets.entries) {
              final fileName = entry.key;
              final meta = entry.value as Map<String, dynamic>?;
              final expectedHash = meta?['sha256'] as String?;
              final file = File('${otaDir.path}/$fileName');
              if (!verifyBundleFile(file, expectedSha256: expectedHash)) {
                return false;
              }
            }
          }
          return true;
        } catch (e) {
          debugPrint('ModelManager: Invalid manifest JSON in dynamic update directory: $e');
          return false;
        }
      }

      // Check if at least one valid model binary or rule exists
      final lookAgainFile = File('${otaDir.path}/look_again.tflite');
      final modelFile = File('${otaDir.path}/model.tflite');
      final rulesFile = File('${otaDir.path}/rules.json');

      final hasLookAgain = verifyBundleFile(lookAgainFile) || verifyBundleFile(modelFile);
      final hasRules = verifyBundleFile(rulesFile);

      return hasLookAgain || hasRules;
    } catch (e) {
      debugPrint('ModelManager: Directory verification error: $e');
      return false;
    }
  }

  /// Resolves look-again regression model file (dynamic update or null for asset fallback).
  Future<File?> getLookAgainModelFile() async {
    try {
      final otaDir = await dynamicModelDirectory;
      final lookAgainFile = File('${otaDir.path}/look_again.tflite');
      if (verifyBundleFile(lookAgainFile)) return lookAgainFile;

      final modelFile = File('${otaDir.path}/model.tflite');
      if (verifyBundleFile(modelFile)) return modelFile;
    } catch (e) {
      debugPrint('ModelManager: Failed resolving look-again model file: $e');
    }
    return null;
  }

  /// Resolves category classifier model file (dynamic update or null for asset fallback).
  Future<File?> getCategoryModelFile() async {
    try {
      final otaDir = await dynamicModelDirectory;
      final categoryFile = File('${otaDir.path}/category_model.tflite');
      if (verifyBundleFile(categoryFile)) return categoryFile;

      final textClassifierFile = File('${otaDir.path}/text_classifier.tflite');
      if (verifyBundleFile(textClassifierFile)) return textClassifierFile;
    } catch (e) {
      debugPrint('ModelManager: Failed resolving category model file: $e');
    }
    return null;
  }

  /// Resolves rules JSON string (dynamic update if valid, else static asset fallback).
  Future<String> getRulesJson() async {
    try {
      final otaDir = await dynamicModelDirectory;
      final rulesFile = File('${otaDir.path}/rules.json');
      if (verifyBundleFile(rulesFile)) {
        return rulesFile.readAsStringSync();
      }
    } catch (e) {
      debugPrint('ModelManager: Failed reading dynamic rules.json: $e');
    }
    return await rootBundle.loadString('assets/rules.json');
  }

  /// Resolves vocabulary file content string (dynamic update if valid, else static asset fallback).
  Future<String> getVocabContent() async {
    try {
      final otaDir = await dynamicModelDirectory;
      final vocabFile = File('${otaDir.path}/vocab.txt');
      if (verifyBundleFile(vocabFile)) {
        return vocabFile.readAsStringSync();
      }
    } catch (e) {
      debugPrint('ModelManager: Failed reading dynamic vocab.txt: $e');
    }
    return await rootBundle.loadString('assets/vocab.txt');
  }

  /// Applies a dynamic ML update bundle atomically with verification checks.
  Future<bool> updateModelBundle(Map<String, List<int>> files, {String? manifestJson}) async {
    Directory? otaDir;
    try {
      otaDir = await dynamicModelDirectory;

      // 1. Write files to temporary staging directory first
      final stagingDir = Directory('${otaDir.path}_staging');
      if (stagingDir.existsSync()) {
        stagingDir.deleteSync(recursive: true);
      }
      stagingDir.createSync(recursive: true);

      if (manifestJson != null && manifestJson.isNotEmpty) {
        final manifestFile = File('${stagingDir.path}/manifest.json');
        manifestFile.writeAsStringSync(manifestJson);
      }

      for (final entry in files.entries) {
        final file = File('${stagingDir.path}/${entry.key}');
        file.writeAsBytesSync(entry.value);
      }

      // 2. Perform verification on staging directory
      final isStagingValid = await verifyDirectory(stagingDir);
      if (!isStagingValid) {
        debugPrint('ModelManager: Dynamic ML update staging verification failed. Aborting update.');
        stagingDir.deleteSync(recursive: true);
        return false;
      }

      // 3. Promote staging files to active otaDir
      if (otaDir.existsSync()) {
        otaDir.deleteSync(recursive: true);
      }
      otaDir.createSync(recursive: true);

      final stagedFiles = stagingDir.listSync();
      for (final entity in stagedFiles) {
        if (entity is File) {
          final targetPath = '${otaDir.path}/${entity.uri.pathSegments.last}';
          entity.copySync(targetPath);
        }
      }

      stagingDir.deleteSync(recursive: true);

      // 4. Update active state
      _isDynamicActive = true;
      _activeVersion = await _resolveManifestVersion(otaDir);
      debugPrint('ModelManager: Dynamic ML model update successfully applied (version: $_activeVersion).');
      return true;
    } catch (e) {
      debugPrint('ModelManager: Exception during updateModelBundle: $e');
      return false;
    }
  }

  /// Clears dynamic ML updates and resets model resolution to static assets.
  Future<void> clearDynamicUpdates() async {
    try {
      final otaDir = await dynamicModelDirectory;
      if (otaDir.existsSync()) {
        otaDir.deleteSync(recursive: true);
      }
      _isDynamicActive = false;
      _activeVersion = '1.0.0-tflite';
      debugPrint('ModelManager: Cleared dynamic ML updates.');
    } catch (e) {
      debugPrint('ModelManager: Failed to clear dynamic ML updates: $e');
    }
  }

  Future<String> _resolveManifestVersion(Directory dir) async {
    final manifestFile = File('${dir.path}/manifest.json');
    if (manifestFile.existsSync()) {
      try {
        final parsed = json.decode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        return parsed['version'] as String? ?? '2.0.0-ota';
      } catch (_) {}
    }
    return '2.0.0-ota';
  }
}
