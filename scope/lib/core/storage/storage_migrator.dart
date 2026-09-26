import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Helper utility to migrate storage files from Documents directory
/// to Application Support directory across platforms and enforce iOS backup exclusion.
class StorageMigrator {
  static const MethodChannel _channel = MethodChannel('com.scope.attentions/storage');
  static Future<void>? _migrationFuture;

  /// Resets internal state for unit testing.
  static void resetForTesting() {
    _migrationFuture = null;
  }

  /// Migrates local SQLite database files and custom RLHF rule files from Documents
  /// to Application Support directory.
  /// 
  /// Optionally accepts [documentsDirOverride] and [supportDirOverride] for testing.
  static Future<void> migrate({Directory? documentsDirOverride, Directory? supportDirOverride}) {
    if (documentsDirOverride != null || supportDirOverride != null) {
      return _doMigrate(documentsDirOverride, supportDirOverride);
    }
    _migrationFuture ??= _doMigrate(null, null);
    return _migrationFuture!;
  }

  static Future<void> _doMigrate(Directory? docDirOverride, Directory? suppDirOverride) async {
    try {
      final documentsDir = docDirOverride ?? await getApplicationDocumentsDirectory();
      final supportDir = suppDirOverride ?? await getApplicationSupportDirectory();

      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }

      // Mark Application Support directory as excluded from backup on iOS
      await _setBackupExclusion(supportDir.path);

      // List of candidate files to migrate
      final baseFilesToMigrate = {
        'attention_os.db',
        'attention_os.db-journal',
        'attention_os.db-shm',
        'attention_os.db-wal',
        'rlhf_rules.json',
      };

      final filesToMigrate = Set<String>.from(baseFilesToMigrate);

      // Scan documents directory for any additional db/rules files
      if (await documentsDir.exists()) {
        try {
          final entities = await documentsDir.list().toList();
          for (final entity in entities) {
            if (entity is File) {
              final fileName = p.basename(entity.path);
              if (fileName.startsWith('attention_os.db') || fileName.startsWith('rlhf_rules.json')) {
                filesToMigrate.add(fileName);
              }
            }
          }
        } catch (_) {}
      }

      for (final fileName in filesToMigrate) {
        final sourceFile = File(p.join(documentsDir.path, fileName));
        final targetFile = File(p.join(supportDir.path, fileName));

        if (await sourceFile.exists()) {
          if (!await targetFile.exists()) {
            final tempTarget = File(p.join(supportDir.path, '$fileName.tmp'));
            try {
              await sourceFile.copy(tempTarget.path);
              final sourceLen = await sourceFile.length();
              final tempLen = await tempTarget.length();

              if (await tempTarget.exists() && tempLen == sourceLen) {
                await tempTarget.rename(targetFile.path);
              } else {
                if (await tempTarget.exists()) {
                  await tempTarget.delete();
                }
                // Migration failed; preserve source file intact
                continue;
              }
            } catch (e) {
              if (await tempTarget.exists()) {
                try {
                  await tempTarget.delete();
                } catch (_) {}
              }
              // Migration failed; preserve source file intact
              // ignore: avoid_print
              print('Failed to migrate $fileName: $e. Source file preserved.');
              continue;
            }
          }

          // Verification succeeded, target file now exists; safely delete source file
          if (await targetFile.exists()) {
            try {
              await sourceFile.delete();
            } catch (e) {
              // ignore: avoid_print
              print('Warning: could not delete legacy source file $fileName: $e');
            }
          }

          // Mark target file as excluded from backup on iOS
          await _setBackupExclusion(targetFile.path);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Storage migration encountered an error: $e');
    }
  }

  static Future<void> _setBackupExclusion(String path) async {
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod('excludeFromBackup', {'path': path});
      } on PlatformException catch (e) {
        // ignore: avoid_print
        print('PlatformException setting backup exclusion on $path: ${e.message}');
      } on MissingPluginException {
        // Expected when running in widget/unit tests without mock channel
      } catch (e) {
        // ignore: avoid_print
        print('Failed to set backup exclusion on $path: $e');
      }
    }
  }
}
