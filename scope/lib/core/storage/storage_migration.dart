import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles automatic migration of database and rule files from user documents storage
/// (`getApplicationDocumentsDirectory`) to application support storage
/// (`getApplicationSupportDirectory`).
class StorageMigration {
  static bool _hasMigrated = false;

  /// Migrates legacy database and rule files from user documents directory to
  /// application support storage.
  static Future<void> migrateLegacyFiles({
    Directory? customDocumentsDir,
    Directory? customSupportDir,
  }) async {
    if (_hasMigrated && customDocumentsDir == null && customSupportDir == null) {
      return;
    }

    try {
      final documentsDir = customDocumentsDir ?? await getApplicationDocumentsDirectory();
      final supportDir = customSupportDir ?? await getApplicationSupportDirectory();

      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }

      final filesToMigrate = [
        'attention_os.db',
        'attention_os.db-journal',
        'attention_os.db-wal',
        'attention_os.db-shm',
        'rlhf_rules.json',
      ];

      for (final fileName in filesToMigrate) {
        final legacyFile = File(p.join(documentsDir.path, fileName));
        final targetFile = File(p.join(supportDir.path, fileName));

        if (await legacyFile.exists()) {
          if (!await targetFile.exists()) {
            try {
              await legacyFile.rename(targetFile.path);
            } catch (_) {
              // Fallback to copy and delete if rename fails across filesystems
              await legacyFile.copy(targetFile.path);
              await legacyFile.delete();
            }
            debugPrint('StorageMigration: Migrated $fileName to application support directory.');
          } else {
            // Target file already exists, remove legacy file to prevent sensitive exposure
            await legacyFile.delete();
            debugPrint('StorageMigration: Cleaned up legacy $fileName as target already exists.');
          }
        }
      }

      if (customDocumentsDir == null && customSupportDir == null) {
        _hasMigrated = true;
      }
    } catch (e) {
      debugPrint('StorageMigration: Error during storage migration: $e');
    }
  }

  @visibleForTesting
  static void resetMigrationState() {
    _hasMigrated = false;
  }
}
