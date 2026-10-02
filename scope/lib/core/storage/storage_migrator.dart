import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Automates migration of internal persistence files from the legacy Documents directory
/// to the Application Support directory on mobile platforms.
class StorageMigrator {
  static Future<void>? _migrationFuture;

  /// Returns the Application Support directory after completing legacy storage migration.
  static Future<Directory> getSupportDirectoryWithMigration() async {
    _migrationFuture ??= _performMigration();
    await _migrationFuture;
    return await getApplicationSupportDirectory();
  }

  /// Explicitly runs the migration logic once.
  static Future<void> migrateLegacyStorage() async {
    _migrationFuture ??= _performMigration();
    await _migrationFuture;
  }

  static Future<void> _performMigration() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final docsDir = await getApplicationDocumentsDirectory();

      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }

      final filesToMigrate = [
        'attention_os.db',
        'attention_os.db-wal',
        'attention_os.db-shm',
        'rlhf_rules.json',
      ];

      for (final fileName in filesToMigrate) {
        final legacyFile = File(p.join(docsDir.path, fileName));
        final targetFile = File(p.join(supportDir.path, fileName));

        if (await legacyFile.exists()) {
          if (!await targetFile.exists()) {
            final tmpFile = File(p.join(supportDir.path, '$fileName.tmp'));
            await legacyFile.copy(tmpFile.path);

            final legacyLength = await legacyFile.length();
            final tmpLength = await tmpFile.length();

            if (legacyLength == tmpLength) {
              await tmpFile.copy(targetFile.path);
              if (await tmpFile.exists()) {
                await tmpFile.delete();
              }
              await legacyFile.delete();
            } else {
              if (await tmpFile.exists()) {
                await tmpFile.delete();
              }
            }
          } else {
            // Target file already exists in Application Support; remove legacy file
            await legacyFile.delete();
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Storage migration error: $e');
    }
  }

  /// Resets the migration lock for isolated unit tests.
  static void resetForTest() {
    _migrationFuture = null;
  }
}
