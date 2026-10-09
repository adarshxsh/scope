import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Central dynamic model loader service managing versioned TFLite models and assets.
class ModelManager {
  static ModelManager? _instance;
  static ModelManager get instance => _instance ??= ModelManager._();

  ModelManager._();

  String _activeVersion = '1.0.0-bundled';
  Map<String, dynamic> _manifest = {};
  Directory? _modelsDirectory;

  /// Custom override directory (used primarily for unit testing).
  void setCustomDirectory(Directory dir) {
    _modelsDirectory = dir;
  }

  String get activeModelVersion => _activeVersion;
  Map<String, dynamic> get manifest => Map.unmodifiable(_manifest);

  /// Initializes ModelManager and loads local dynamic manifest if present.
  Future<void> initialize() async {
    try {
      if (_modelsDirectory == null) {
        final docsDir = await getApplicationSupportDirectory();
        _modelsDirectory = Directory(p.join(docsDir.path, 'models'));
      }

      if (_modelsDirectory != null && await _modelsDirectory!.exists()) {
        final manifestFile = File(p.join(_modelsDirectory!.path, 'manifest.json'));
        if (await manifestFile.exists()) {
          final content = await manifestFile.readAsString();
          _manifest = jsonDecode(content) as Map<String, dynamic>;
          if (_manifest.containsKey('version')) {
            _activeVersion = _manifest['version'].toString();
          }
        }
      }
    } catch (e) {
      debugPrint('ModelManager initialization warning: $e');
    }
  }

  /// Returns File handle if file exists in dynamic models directory.
  Future<File?> getLocalModelFile(String fileName) async {
    try {
      if (_modelsDirectory == null) {
        await initialize();
      }
      if (_modelsDirectory != null) {
        final file = File(p.join(_modelsDirectory!.path, fileName));
        if (await file.exists()) {
          return file;
        }
      }
    } catch (e) {
      debugPrint('ModelManager getLocalModelFile error for $fileName: $e');
    }
    return null;
  }

  /// Loads string asset from dynamic storage or falls back to rootBundle asset.
  Future<String> loadString(String fileName, {String? defaultAssetPath}) async {
    final localFile = await getLocalModelFile(fileName);
    if (localFile != null) {
      return await localFile.readAsString();
    }
    return await rootBundle.loadString(defaultAssetPath ?? 'assets/$fileName');
  }

  /// Loads TFLite Interpreter from dynamic storage or falls back to rootBundle asset.
  Future<Interpreter?> loadInterpreter(String fileName, String defaultAssetPath) async {
    final localFile = await getLocalModelFile(fileName);
    if (localFile != null) {
      try {
        debugPrint('ModelManager: Loading dynamic model $fileName from ${localFile.path}');
        return Interpreter.fromFile(localFile);
      } catch (e) {
        debugPrint('ModelManager: Failed to load dynamic model $fileName ($e), falling back to asset $defaultAssetPath');
      }
    }

    try {
      debugPrint('ModelManager: Loading asset model from $defaultAssetPath');
      return await Interpreter.fromAsset(defaultAssetPath);
    } catch (e) {
      debugPrint('ModelManager: Failed to load asset interpreter from $defaultAssetPath: $e');
      return null;
    }
  }

  /// Validates SHA-256 checksums and persists a new model bundle to dynamic storage.
  Future<bool> saveBundle({
    required Map<String, List<int>> files,
    required Map<String, dynamic> manifestJson,
  }) async {
    try {
      if (_modelsDirectory == null) {
        await initialize();
      }
      if (_modelsDirectory == null) return false;

      if (!await _modelsDirectory!.exists()) {
        await _modelsDirectory!.create(recursive: true);
      }

      final manifestFiles = manifestJson['files'] as Map<String, dynamic>? ?? {};

      // 1. Checksum verification before writing
      for (final entry in files.entries) {
        final filename = entry.key;
        final bytes = entry.value;

        if (manifestFiles.containsKey(filename)) {
          final expectedHash = (manifestFiles[filename]['sha256'] ?? '').toString().toLowerCase();
          final actualHash = sha256.convert(bytes).toString().toLowerCase();

          if (expectedHash.isNotEmpty && expectedHash != actualHash) {
            debugPrint('ModelManager: Checksum mismatch for $filename! Expected $expectedHash, got $actualHash');
            return false;
          }
        }
      }

      // 2. Persist files to disk
      for (final entry in files.entries) {
        final file = File(p.join(_modelsDirectory!.path, entry.key));
        await file.writeAsBytes(entry.value);
      }

      // 3. Persist manifest.json
      final manifestFile = File(p.join(_modelsDirectory!.path, 'manifest.json'));
      await manifestFile.writeAsString(jsonEncode(manifestJson));

      _manifest = manifestJson;
      _activeVersion = manifestJson['version']?.toString() ?? '1.0.0-ota';
      debugPrint('ModelManager: Successfully saved OTA model bundle version $_activeVersion');
      return true;
    } catch (e) {
      debugPrint('ModelManager: Failed to save bundle: $e');
      return false;
    }
  }

  /// Clears dynamic models directory (used for testing or resetting to asset defaults).
  Future<void> clearDynamicModels() async {
    try {
      if (_modelsDirectory != null && await _modelsDirectory!.exists()) {
        await _modelsDirectory!.delete(recursive: true);
      }
      _activeVersion = '1.0.0-bundled';
      _manifest = {};
    } catch (e) {
      debugPrint('ModelManager: Failed to clear dynamic models: $e');
    }
  }
}
