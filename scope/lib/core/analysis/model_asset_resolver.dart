import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Lightweight dual-storage path resolver that checks the local application support
/// storage directory (`getApplicationSupportDirectory()/ml_assets/`) for updated model weights
/// and rule definitions, falling back to bundled package assets when local assets are missing or invalid.
class ModelAssetResolver {
  /// Directory name inside application support directory for ML and rule assets.
  static const String mlAssetsSubdir = 'ml_assets';

  /// Global override directory path (primarily used for test harness injection).
  static String? overrideDirectoryPath;

  ModelAssetResolver._();

  /// Resolves the storage Directory for ML assets (`getApplicationSupportDirectory()/ml_assets/`).
  static Future<Directory?> getMlAssetsDirectory({String? customDirectoryPath}) async {
    final overridePath = customDirectoryPath ?? overrideDirectoryPath;
    if (overridePath != null) {
      return Directory(overridePath);
    }
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      return Directory(path.join(appSupportDir.path, mlAssetsSubdir));
    } catch (e) {
      debugPrint('ModelAssetResolver: Could not resolve application support directory: $e');
      return null;
    }
  }

  /// Checks if a non-empty local file exists in the `ml_assets` directory.
  /// Automatically deletes zero-byte files if encountered.
  static Future<File?> resolveLocalFile(
    String fileName, {
    String? customDirectoryPath,
  }) async {
    try {
      final mlDir = await getMlAssetsDirectory(customDirectoryPath: customDirectoryPath);
      if (mlDir == null || !await mlDir.exists()) {
        return null;
      }

      final localFile = File(path.join(mlDir.path, fileName));
      if (!await localFile.exists()) {
        return null;
      }

      final length = await localFile.length();
      if (length == 0) {
        debugPrint('ModelAssetResolver: Found zero-byte local asset file at ${localFile.path}. Deleting.');
        await _safeDeleteFile(localFile);
        return null;
      }

      return localFile;
    } catch (e) {
      debugPrint('ModelAssetResolver: Error checking local file $fileName: $e');
      return null;
    }
  }

  /// Resolves TFLite Interpreter from local `ml_assets` if present and valid.
  /// If the local file is missing, empty, or fails initialization, safely deletes
  /// any corrupted file and falls back to bundled package assets via `Interpreter.fromAsset`.
  static Future<Interpreter?> resolveInterpreter({
    String fileName = 'model.tflite',
    String assetPath = 'assets/model.tflite',
    String? customDirectoryPath,
  }) async {
    // 1. Try local file in application support directory
    final localFile = await resolveLocalFile(fileName, customDirectoryPath: customDirectoryPath);
    if (localFile != null) {
      try {
        final interpreter = Interpreter.fromFile(localFile);
        debugPrint('ModelAssetResolver: Loaded TFLite model from local file: ${localFile.path}');
        return interpreter;
      } catch (e) {
        debugPrint('ModelAssetResolver: Corrupted or invalid local TFLite model file at ${localFile.path}: $e. Deleting and falling back to asset.');
        await _safeDeleteFile(localFile);
      }
    }

    // 2. Fallback to bundled package asset
    try {
      final interpreter = await Interpreter.fromAsset(assetPath);
      debugPrint('ModelAssetResolver: Loaded TFLite model from bundled asset: $assetPath');
      return interpreter;
    } catch (e) {
      debugPrint('ModelAssetResolver: Failed to load bundled asset $assetPath: $e');
      return null;
    }
  }

  /// Resolves text content (e.g., `rules.json`, `vocab.txt`) from local `ml_assets` if valid,
  /// falling back to bundled package assets via `rootBundle.loadString`.
  static Future<String?> resolveString({
    required String fileName,
    required String assetPath,
    String? customDirectoryPath,
  }) async {
    // 1. Try local file in application support directory
    final localFile = await resolveLocalFile(fileName, customDirectoryPath: customDirectoryPath);
    if (localFile != null) {
      try {
        final content = await localFile.readAsString();
        if (content.trim().isNotEmpty) {
          debugPrint('ModelAssetResolver: Loaded local string asset from ${localFile.path}');
          return content;
        } else {
          debugPrint('ModelAssetResolver: Empty string content in local asset file ${localFile.path}. Deleting.');
          await _safeDeleteFile(localFile);
        }
      } catch (e) {
        debugPrint('ModelAssetResolver: Failed to read local string asset file ${localFile.path}: $e. Deleting.');
        await _safeDeleteFile(localFile);
      }
    }

    // 2. Fallback to bundled package asset
    try {
      final content = await rootBundle.loadString(assetPath);
      debugPrint('ModelAssetResolver: Loaded string asset from bundled asset: $assetPath');
      return content;
    } catch (e) {
      debugPrint('ModelAssetResolver: Failed to load bundled string asset $assetPath: $e');
      return null;
    }
  }

  /// Convenience helper for resolving classification rules JSON.
  static Future<String?> resolveRules({
    String fileName = 'rules.json',
    String assetPath = 'assets/rules.json',
    String? customDirectoryPath,
  }) {
    return resolveString(
      fileName: fileName,
      assetPath: assetPath,
      customDirectoryPath: customDirectoryPath,
    );
  }

  /// Convenience helper for resolving vocabulary text.
  static Future<String?> resolveVocab({
    String fileName = 'vocab.txt',
    String assetPath = 'assets/vocab.txt',
    String? customDirectoryPath,
  }) {
    return resolveString(
      fileName: fileName,
      assetPath: assetPath,
      customDirectoryPath: customDirectoryPath,
    );
  }

  /// Safely deletes a file without raising unhandled exceptions.
  static Future<void> _safeDeleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('ModelAssetResolver: Failed to delete file at ${file.path}: $e');
    }
  }
}
