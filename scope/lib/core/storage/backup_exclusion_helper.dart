import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Helper to set native backup exclusion attributes (e.g. NSURLIsExcludedFromBackupKey on iOS)
/// on sensitive persistent storage files such as SQLite databases and custom RLHF rule files.
class BackupExclusionHelper {
  static const MethodChannel _channel = MethodChannel('com.scope.attentions/storage');
  static const MethodChannel _fallbackChannel = MethodChannel('com.scope.backup');

  /// Applies backup exclusion to a specific file path.
  /// Catches [MissingPluginException] and [PlatformException] gracefully when running in headless
  /// test runners or on unsupported platforms.
  static Future<bool> excludeFromBackup(String path) async {
    if (path.isEmpty) return false;
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }

      bool? result;
      try {
        result = await _channel.invokeMethod<bool>('excludeFromBackup', {'path': path});
      } on MissingPluginException {
        // Fall back to alternative channel name if registered
        try {
          result = await _fallbackChannel.invokeMethod<bool>('excludeFromBackup', {'path': path});
        } catch (_) {
          return false;
        }
      } on PlatformException {
        return false;
      }
      return result ?? true;
    } on MissingPluginException {
      // Ignored in unit/widget test environments
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Finds and sets backup exclusion attributes on all standard application database
  /// and rule files across Documents and Application Support directories.
  static Future<void> excludeDatabaseAndRules() async {
    try {
      final searchDirectories = <Directory>[];

      try {
        final docs = await getApplicationDocumentsDirectory();
        searchDirectories.add(docs);
      } catch (_) {}

      try {
        final support = await getApplicationSupportDirectory();
        searchDirectories.add(support);
      } catch (_) {}

      final targetFiles = [
        'attention_os.db',
        'attention_os.db-wal',
        'attention_os.db-shm',
        'rlhf_rules.json',
      ];

      for (final dir in searchDirectories) {
        for (final fileName in targetFiles) {
          final filePath = p.join(dir.path, fileName);
          await excludeFromBackup(filePath);
        }
      }
    } catch (_) {
      // Graceful error suppression during storage initialization
    }
  }
}
