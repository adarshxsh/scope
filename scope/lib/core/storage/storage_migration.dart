import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Handles migration of legacy storage files from the Application Documents
/// directory to Application Support directory and applies backup exclusion flags.
class StorageMigration {
  static const MethodChannel _backupChannel = MethodChannel('com.scope.backup_exclusion');

  /// Known files to migrate from Documents to Application Support storage.
  static const List<String> _filesToMigrate = [
    'attention_os.db',
    'attention_os.db-journal',
    'attention_os.db-wal',
    'attention_os.db-shm',
    'rlhf_rules.json',
  ];

  /// Migrates legacy files from [docsDir] to [supportDir] if they exist in [docsDir]
  /// and do not yet exist in [supportDir].
  ///
  /// Operations catch file I/O exceptions to preserve existing legacy files if a
  /// move operation encounters filesystem permission errors or issues.
  static Future<void> migrateLegacyFiles({
    required Directory docsDir,
    required Directory supportDir,
  }) async {
    try {
      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }

      // Exclude support directory from cloud backups on iOS
      if (Platform.isIOS) {
        await excludeFromBackup(supportDir.path);
      }

      for (final fileName in _filesToMigrate) {
        final legacyFile = File(p.join(docsDir.path, fileName));
        final targetFile = File(p.join(supportDir.path, fileName));

        // Avoid migrating if source and destination paths are identical
        if (legacyFile.path == targetFile.path) continue;

        if (await legacyFile.exists()) {
          if (!await targetFile.exists()) {
            try {
              // Attempt atomic file move
              await legacyFile.rename(targetFile.path);
            } catch (e) {
              // Fallback to copy and delete if rename fails (e.g., cross-device)
              try {
                await legacyFile.copy(targetFile.path);
                await legacyFile.delete();
              } catch (copyError) {
                // Preserve existing legacy file on failure
                // ignore: avoid_print
                print('StorageMigration: failed to migrate $fileName: $copyError');
              }
            }
          }

          if (await targetFile.exists() && Platform.isIOS) {
            await excludeFromBackup(targetFile.path);
          }
        } else if (await targetFile.exists() && Platform.isIOS) {
          await excludeFromBackup(targetFile.path);
        }
      }
    } catch (e) {
      // Catch filesystem level errors to avoid crashing app startup
      // ignore: avoid_print
      print('StorageMigration: unexpected error during migration: $e');
    }
  }

  /// Marks a file or directory at [path] as excluded from iCloud/iTunes backups on iOS
  /// using native file attributes (NSURLIsExcludedFromBackupKey).
  static Future<void> excludeFromBackup(String path) async {
    if (!Platform.isIOS) return;
    try {
      await _backupChannel.invokeMethod('excludeFromBackup', {'path': path});
    } catch (e) {
      // Ignore errors when native channel is missing (e.g. unit test runner)
    }
  }
}
