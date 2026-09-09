import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Manages local filesystem storage for machine learning models and vocabularies.
///
/// Resolves dynamic updates from application document storage while falling back
/// to bundled package assets. Supports atomic file replacement and validation.
class ModelStorageManager {
  static ModelStorageManager? _instance;

  final Directory? _baseDirectory;
  final String modelFileName;
  final String vocabFileName;
  final String bundledModelAsset;
  final String bundledVocabAsset;

  ModelStorageManager({
    Directory? baseDirectory,
    this.modelFileName = 'model.tflite',
    this.vocabFileName = 'vocab.txt',
    this.bundledModelAsset = 'assets/model.tflite',
    this.bundledVocabAsset = 'assets/vocab.txt',
  }) : _baseDirectory = baseDirectory;

  /// Singleton instance using default application storage directories.
  static ModelStorageManager get instance => _instance ??= ModelStorageManager();

  /// Sets the global singleton instance (useful for testing or custom configuration).
  static set instance(ModelStorageManager manager) => _instance = manager;

  /// Returns the target directory for storing local model assets.
  Future<Directory> getStorageDirectory() async {
    if (_baseDirectory != null) {
      if (!await _baseDirectory.exists()) {
        await _baseDirectory.create(recursive: true);
      }
      return _baseDirectory;
    }
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDocDir.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      return modelsDir;
    } catch (e) {
      // Fallback for test environments where path_provider is uninitialized
      final tempDir = Directory('${Directory.systemTemp.path}/scope_models');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      return tempDir;
    }
  }

  /// Gets the local model file handle.
  Future<File> getModelFile() async {
    final dir = await getStorageDirectory();
    return File('${dir.path}/$modelFileName');
  }

  /// Gets the local vocabulary file handle.
  Future<File> getVocabFile() async {
    final dir = await getStorageDirectory();
    return File('${dir.path}/$vocabFileName');
  }

  /// Checks if a valid non-empty local model file exists.
  Future<bool> hasLocalModel() async {
    try {
      final file = await getModelFile();
      return await file.exists() && (await file.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a valid non-empty local vocabulary file exists.
  Future<bool> hasLocalVocab() async {
    try {
      final file = await getVocabFile();
      return await file.exists() && (await file.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Atomically saves model bytes to local storage using temporary file replacement.
  Future<File> saveModelBytes(List<int> bytes) async {
    final dir = await getStorageDirectory();
    final targetFile = File('${dir.path}/$modelFileName');
    final tempFile = File('${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');

    await tempFile.writeAsBytes(bytes, flush: true);

    try {
      return await tempFile.rename(targetFile.path);
    } catch (e) {
      // Fallback if atomic rename fails across filesystem partitions
      await tempFile.copy(targetFile.path);
      await tempFile.delete();
      return targetFile;
    }
  }

  /// Atomically saves vocabulary content string to local storage using temporary file replacement.
  Future<File> saveVocabContent(String content) async {
    final dir = await getStorageDirectory();
    final targetFile = File('${dir.path}/$vocabFileName');
    final tempFile = File('${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');

    await tempFile.writeAsString(content, flush: true);

    try {
      return await tempFile.rename(targetFile.path);
    } catch (e) {
      await tempFile.copy(targetFile.path);
      await tempFile.delete();
      return targetFile;
    }
  }

  /// Loads model bytes from local file if available, falling back to static package asset.
  Future<Uint8List> loadModelBytes() async {
    if (await hasLocalModel()) {
      try {
        final file = await getModelFile();
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('ModelStorageManager: Failed reading local model file, falling back to asset: $e');
        await deleteLocalModel();
      }
    }

    final byteData = await rootBundle.load(bundledModelAsset);
    return byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
  }

  /// Loads vocabulary content string from local file if available, falling back to static package asset.
  Future<String> loadVocabContent() async {
    if (await hasLocalVocab()) {
      try {
        final file = await getVocabFile();
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return content;
        }
      } catch (e) {
        debugPrint('ModelStorageManager: Failed reading local vocab file, falling back to asset: $e');
        await deleteLocalVocab();
      }
    }

    return await rootBundle.loadString(bundledVocabAsset);
  }

  /// Deletes the local model file if present.
  Future<void> deleteLocalModel() async {
    try {
      final file = await getModelFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('ModelStorageManager: Error deleting local model file: $e');
    }
  }

  /// Deletes the local vocabulary file if present.
  Future<void> deleteLocalVocab() async {
    try {
      final file = await getVocabFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('ModelStorageManager: Error deleting local vocab file: $e');
    }
  }

  /// Clears all local dynamic assets.
  Future<void> clearAll() async {
    await deleteLocalModel();
    await deleteLocalVocab();
  }
}
