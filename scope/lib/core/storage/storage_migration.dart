import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/storage/backup_exclusion.dart';

/// Class responsible for migrating application files from legacy Documents directory
/// to the Application Support directory on application startup.
class StorageMigrator {
  static Future<void>? _activeMigration;

  /// Default list of legacy files to migrate to Application Support.
  static const List<String> _legacyFiles = [
    'attention_os.db',
    'attention_os.db-journal',
    'attention_os.db-shm',
    'attention_os.db-wal',
    'rlhf_rules.json',
  ];

  /// Runs the automated migration process if legacy files exist in Documents directory.
  /// Guarantees thread-safe / atomic execution across concurrent callers.
  static Future<void> migrate({Directory? customLegacyDir, Directory? customTargetDir}) async {
    if (_activeMigration != null) {
      return _activeMigration;
    }

    final completer = Completer<void>();
    _activeMigration = completer.future;

    try {
      final legacyDir = customLegacyDir ?? await _getDocumentsDirectory();
      final targetDir = customTargetDir ?? await _getApplicationSupportDirectory();

      if (legacyDir != null && targetDir != null) {
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        // Exclude target directory from backups on iOS
        await BackupExclusionService.excludeFromBackup(targetDir.path);

        for (final fileName in _legacyFiles) {
          final legacyFile = File(p.join(legacyDir.path, fileName));
          if (!await legacyFile.exists()) {
            continue;
          }

          final targetFile = File(p.join(targetDir.path, fileName));
          final legacyLength = await legacyFile.length();

          // Handle conflict: target file already exists
          if (await targetFile.exists()) {
            final targetLength = await targetFile.length();
            if (targetLength > 0 && _verifyIntegrity(targetFile, fileName)) {
              // Target is already intact and valid, delete legacy file to conclude migration
              try {
                await legacyFile.delete();
              } catch (_) {}
              await BackupExclusionService.excludeFromBackup(targetFile.path);
              continue;
            }
          }

          // Atomic move strategy using temporary file
          final tempFile = File(p.join(targetDir.path, '$fileName.tmp'));
          if (await tempFile.exists()) {
            await tempFile.delete();
          }

          await legacyFile.copy(tempFile.path);

          // Verify copied file integrity
          final tempLength = await tempFile.length();
          final isValid = tempLength == legacyLength && _verifyIntegrity(tempFile, fileName);

          if (isValid) {
            // Atomic overwrite/rename
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            await tempFile.rename(targetFile.path);

            // Set iOS backup exclusion flag on target file
            await BackupExclusionService.excludeFromBackup(targetFile.path);

            // Delete legacy file after successful move
            await legacyFile.delete();
          } else {
            // Cleanup invalid temp file if copy was corrupt
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          }
        }
      }
      completer.complete();
    } catch (e) {
      // Complete with error or complete normally to avoid blocking app boot
      completer.complete();
    } finally {
      _activeMigration = null;
    }
  }

  /// Verifies file integrity based on file type.
  static bool _verifyIntegrity(File file, String fileName) {
    try {
      if (!file.existsSync()) return false;
      if (file.lengthSync() == 0) return false;

      if (fileName.endsWith('.json')) {
        final content = file.readAsStringSync();
        json.decode(content);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Directory?> _getDocumentsDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  static Future<Directory?> _getApplicationSupportDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }
}
