import 'package:flutter/services.dart';

/// Helper for setting platform-specific backup exclusion attributes.
class BackupExclusionHelper {
  static const MethodChannel _channel = MethodChannel('scope/backup_protection');

  /// Sets NSURLIsExcludedFromBackupKey on iOS (and platform-specific attributes)
  /// for the specified file path. Fails gracefully if channel is unavailable or fails.
  static Future<bool> excludeFromBackup(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('excludeFromBackup', {
        'path': filePath,
      });
      return result ?? false;
    } on MissingPluginException {
      // Gracefully handle unhandled platform channel in test runner or desktop
      return false;
    } on PlatformException {
      // Gracefully handle platform error
      return false;
    } catch (_) {
      return false;
    }
  }
}
