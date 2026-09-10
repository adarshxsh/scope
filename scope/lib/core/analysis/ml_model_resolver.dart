import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves dynamic ML model assets (TFLite binaries, vocabularies, rule definitions)
/// from local application storage directories before falling back to static bundled assets.
class MLModelResolver {
  final List<Directory>? customDirectories;

  MLModelResolver({this.customDirectories});

  /// Searches local application storage for [fileName].
  /// Checks existence, size, and format integrity before returning the [File].
  /// Returns `null` if the file is missing or fails integrity checks.
  Future<File?> resolveModelFile(String fileName) async {
    final searchDirs = await _getSearchDirectories();

    for (final dir in searchDirs) {
      try {
        final filePath = '${dir.path}/$fileName';
        final file = File(filePath);

        if (await file.exists()) {
          final isValid = await validateFileIntegrity(file, fileName);
          if (isValid) {
            debugPrint('MLModelResolver: Resolved valid local asset at "$filePath".');
            return file;
          } else {
            debugPrint('MLModelResolver: Local file "$filePath" failed integrity check.');
          }
        }
      } catch (e) {
        debugPrint('MLModelResolver: Exception checking file "$fileName" in "${dir.path}": $e');
      }
    }

    debugPrint('MLModelResolver: No valid local asset found for "$fileName".');
    return null;
  }

  /// Validates file existence, non-zero file size, and header/syntax integrity.
  Future<bool> validateFileIntegrity(File file, String fileName) async {
    try {
      if (!await file.exists()) {
        return false;
      }

      final length = await file.length();
      if (length <= 0) {
        debugPrint('MLModelResolver Integrity Failure: "$fileName" is empty (0 bytes).');
        return false;
      }

      final lowerName = fileName.toLowerCase();

      // 1. TFLite model binary validation
      if (lowerName.endsWith('.tflite')) {
        if (length < 8) {
          debugPrint('MLModelResolver Integrity Failure: "$fileName" too short for TFLite header.');
          return false;
        }

        final bytes = await file.openRead(0, 8).first;
        if (bytes.length < 8) {
          return false;
        }

        // TFLite flatbuffers schema identifier at offset 4..6 is 'TFL' (0x54, 0x46, 0x4C)
        final isTfliteHeader = bytes[4] == 0x54 && bytes[5] == 0x46 && bytes[6] == 0x4C;
        if (!isTfliteHeader) {
          debugPrint('MLModelResolver Integrity Failure: "$fileName" invalid TFLite header bytes.');
          return false;
        }
      }
      // 2. JSON rule database validation
      else if (lowerName.endsWith('.json')) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) return false;
        json.decode(content);
      }
      // 3. Vocabulary text file validation
      else if (lowerName.endsWith('.txt')) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) return false;
      }

      return true;
    } catch (e) {
      debugPrint('MLModelResolver Integrity Check Error for "$fileName": $e');
      return false;
    }
  }

  Future<List<Directory>> _getSearchDirectories() async {
    final dirs = <Directory>[];

    if (customDirectories != null && customDirectories!.isNotEmpty) {
      dirs.addAll(customDirectories!);
    }

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      if (!dirs.any((d) => d.path == appSupportDir.path)) {
        dirs.add(appSupportDir);
      }
    } catch (e) {
      // Path provider may throw in test environments without channel implementations
      debugPrint('MLModelResolver: getApplicationSupportDirectory unavailable: $e');
    }

    try {
      final appDocsDir = await getApplicationDocumentsDirectory();
      if (!dirs.any((d) => d.path == appDocsDir.path)) {
        dirs.add(appDocsDir);
      }
    } catch (e) {
      debugPrint('MLModelResolver: getApplicationDocumentsDirectory unavailable: $e');
    }

    return dirs;
  }
}
