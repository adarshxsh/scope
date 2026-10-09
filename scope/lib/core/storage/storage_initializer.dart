import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles secure local storage initialization, legacy directory migration,
/// and setting iOS non-backup resource flags.
class StorageInitializer {
  static const MethodChannel _channel = MethodChannel('com.scope.notifications');

  /// Resolves the secure Application Support storage file path for [fileName].
  ///
  /// Automatically migrates legacy files from Documents directory if present,
  /// and applies iOS non-backup resource flags.
  static Future<File> prepareStorageFile(
    String fileName, {
    Directory? overrideDocumentsDir,
    Directory? overrideSupportDir,
  }) async {
    final docsDir = overrideDocumentsDir ?? await getApplicationDocumentsDirectory();
    final supportDir = overrideSupportDir ?? await getApplicationSupportDirectory();

    if (!supportDir.existsSync()) {
      supportDir.createSync(recursive: true);
    }

    final legacyFile = File(p.join(docsDir.path, fileName));
    final targetFile = File(p.join(supportDir.path, fileName));

    // Automated migration check: Move legacy files from documents directory to Application Support
    if (legacyFile.existsSync() && !targetFile.existsSync()) {
      _moveFile(legacyFile, targetFile);

      // Check for related SQLite journal/WAL sidecars if applicable
      for (final ext in ['-wal', '-shm', '-journal']) {
        final legacyAux = File(p.join(docsDir.path, '$fileName$ext'));
        final targetAux = File(p.join(supportDir.path, '$fileName$ext'));
        if (legacyAux.existsSync() && !targetAux.existsSync()) {
          _moveFile(legacyAux, targetAux);
        }
      }
    }

    if (!targetFile.existsSync()) {
      targetFile.createSync(recursive: true);
    }

    await applyNonBackupFlag(targetFile);

    return targetFile;
  }

  /// Sets iOS non-backup resource flags on [file] to exclude it from iCloud/iTunes backups.
  static Future<void> applyNonBackupFlag(File file) async {
    if (!file.existsSync()) return;

    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod('setNonBackupFlag', {'path': file.path});
      } on MissingPluginException {
        // Ignored in unit test execution
      } on PlatformException catch (e) {
        // ignore: avoid_print
        print('StorageInitializer: Failed to set non-backup flag via channel: ${e.message}');
      }
    }

    if (Platform.isIOS || Platform.isMacOS) {
      try {
        await Process.run('xattr', ['-w', 'com.apple.MobileBackup', '1', file.path]);
      } catch (_) {
        // Best-effort fallback
      }
    }
  }

  static void _moveFile(File src, File dest) {
    try {
      src.renameSync(dest.path);
    } catch (_) {
      src.copySync(dest.path);
      src.deleteSync();
    }
  }
}
