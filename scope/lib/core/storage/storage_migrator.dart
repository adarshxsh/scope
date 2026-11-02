import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/storage/backup_exclusion_helper.dart';

/// Handles storage relocation from Documents to Application Support directory
/// and applies backup exclusion attributes to persistent database and rules files.
class StorageMigrator {
  static bool _migrated = false;

  /// Migrates legacy database and RLHF rules files from Documents to Application Support
  /// directory and applies backup exclusion attributes to persistent files.
  static Future<void> migrate() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final supportDir = await getApplicationSupportDirectory();

      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }

      final filesToMigrate = [
        'attention_os.db',
        'attention_os.db-wal',
        'attention_os.db-shm',
        'attention_os.db-journal',
        'rlhf_rules.json',
      ];

      for (final fileName in filesToMigrate) {
        final legacyFile = File(p.join(docsDir.path, fileName));
        final targetFile = File(p.join(supportDir.path, fileName));

        if (await legacyFile.exists()) {
          if (!await targetFile.exists()) {
            await legacyFile.copy(targetFile.path);
          }
          if (await targetFile.exists()) {
            await legacyFile.delete();
          }
        }

        if (await targetFile.exists()) {
          await BackupExclusionHelper.excludeFromBackup(targetFile.path);
        }
      }

      _migrated = true;
    } catch (e) {
      // ignore: avoid_print
      print('Storage migration error: $e');
    }
  }

  /// Returns true if migration was completed during the current process run.
  static bool get isMigrated => _migrated;
}
