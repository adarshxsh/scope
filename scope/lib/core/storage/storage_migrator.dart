import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/storage/backup_exclusion_helper.dart';

/// Manages storage locations and migration from Application Documents directory
/// to Application Support directory with iOS backup exclusion.
class StorageMigrator {
  /// Gets the Application Support Directory, ensuring it exists and has backup exclusion applied.
  static Future<Directory> getAppSupportDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    if (!await supportDir.exists()) {
      await supportDir.create(recursive: true);
    }
    await BackupExclusionHelper.excludeFromBackup(supportDir.path);
    return supportDir;
  }

  /// Migrates legacy persistent files from Documents directory to Support directory.
  /// Uses atomic copy-and-verify semantics to prevent cross-device [FileSystemException] errors.
  static Future<void> migrateLegacyFiles() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final supportDir = await getAppSupportDirectory();

      final legacyFileNames = [
        'attention_os.db',
        'attention_os.db-wal',
        'attention_os.db-shm',
        'rlhf_rules.json',
      ];

      for (final fileName in legacyFileNames) {
        final legacyFile = File(p.join(docsDir.path, fileName));
        final targetFile = File(p.join(supportDir.path, fileName));

        if (await legacyFile.exists()) {
          if (!await targetFile.exists() || (await targetFile.length()) == 0) {
            final tempFile = File('${targetFile.path}.tmp');
            await legacyFile.copy(tempFile.path);

            if (await tempFile.exists() && (await tempFile.length()) == (await legacyFile.length())) {
              if (await targetFile.exists()) {
                await targetFile.delete();
              }
              await tempFile.rename(targetFile.path);
              await legacyFile.delete();
            } else if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } else {
            // Target file already exists and is valid; delete legacy file
            await legacyFile.delete();
          }
        }

        if (await targetFile.exists()) {
          await BackupExclusionHelper.excludeFromBackup(targetFile.path);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('StorageMigrator error during migration: $e');
    }
  }

  /// Resolves a file inside the Application Support directory, ensuring migration from legacy location
  /// and applying backup exclusion flags.
  static Future<File> resolveSupportFile(String fileName) async {
    await migrateLegacyFiles();
    final supportDir = await getAppSupportDirectory();
    final targetFile = File(p.join(supportDir.path, fileName));
    if (await targetFile.exists()) {
      await BackupExclusionHelper.excludeFromBackup(targetFile.path);
    }
    return targetFile;
  }
}
