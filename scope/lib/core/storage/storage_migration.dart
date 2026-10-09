import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles automated, idempotent migration of internal storage files
/// (SQLite database and custom RLHF rules) from the legacy Documents directory
/// to the Application Support directory.
class StorageMigrationService {
  static const MethodChannel _channel = MethodChannel('com.scope.attentions/storage');
  static bool _hasMigrated = false;

  /// Internal database and rule file names to migrate.
  static const List<String> _migratedFiles = [
    'attention_os.db',
    'attention_os.db-journal',
    'attention_os.db-wal',
    'attention_os.db-shm',
    'rlhf_rules.json',
  ];

  /// Moves legacy database and rule files from Documents to Application Support.
  /// This operation is idempotent and safe to call multiple times.
  /// Optional [legacyDir] and [supportDir] parameters allow injecting custom
  /// directories for unit testing.
  static Future<void> migrateStorage({
    Directory? legacyDir,
    Directory? supportDir,
    bool force = false,
  }) async {
    if (_hasMigrated && !force && legacyDir == null && supportDir == null) {
      return;
    }

    try {
      final Directory sourceDir = legacyDir ?? await getApplicationDocumentsDirectory();
      final Directory targetDir = supportDir ?? await getApplicationSupportDirectory();

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      if (await sourceDir.exists()) {
        for (final fileName in _migratedFiles) {
          final sourceFile = File(p.join(sourceDir.path, fileName));
          final targetFile = File(p.join(targetDir.path, fileName));

          if (await sourceFile.exists()) {
            if (!await targetFile.exists()) {
              try {
                await sourceFile.rename(targetFile.path);
              } catch (_) {
                // Fallback for cross-device/filesystem moves
                await sourceFile.copy(targetFile.path);
                await sourceFile.delete();
              }
            } else {
              // Legacy file is redundant if target already exists; clean it up
              try {
                await sourceFile.delete();
              } catch (_) {}
            }
          }
        }
      }

      // Notify iOS native layer to enforce NSURLIsExcludedFromBackupKey
      if (Platform.isIOS) {
        try {
          await _channel.invokeMethod('excludeFromBackup');
        } catch (_) {
          // Ignore channel errors if unhandled or in test environment
        }
      }

      if (legacyDir == null && supportDir == null) {
        _hasMigrated = true;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Storage migration notice: $e');
    }
  }

  /// Resets internal migration state (used during unit testing).
  static void resetForTest() {
    _hasMigrated = false;
  }
}
