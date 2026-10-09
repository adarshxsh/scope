import 'package:flutter/services.dart';

/// Helper class for setting platform-specific non-backup attributes on sensitive files.
class BackupExclusionHelper {
  static const MethodChannel _channel = MethodChannel('scope/backup_protection');

  /// Applies non-backup resource attributes on the given file path (e.g. iOS NSURLIsExcludedFromBackupKey).
  static Future<void> excludeFromBackup(String filePath) async {
    try {
      await _channel.invokeMethod('excludeFromBackup', {
        'path': filePath,
        'filePath': filePath,
      });
    } on MissingPluginException {
      // Native platform channel not available in unit test runner
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Backup exclusion platform exception: ${e.message}');
    } catch (e) {
      // ignore: avoid_print
      print('Backup exclusion error: $e');
    }
  }
}
