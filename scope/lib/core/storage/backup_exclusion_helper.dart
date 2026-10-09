import 'dart:io';
import 'package:flutter/services.dart';

/// Helper to set backup exclusion attributes on persistent application storage files on iOS.
class BackupExclusionHelper {
  static const MethodChannel _channel = MethodChannel('scope/backup_protection');

  /// Marks a file or directory path as excluded from cloud and OS backups (e.g. iCloud).
  /// Catches [MissingPluginException] and [PlatformException] gracefully during unit tests
  /// or when executing on unsupported platforms.
  static Future<bool> excludeFromBackup(String path) async {
    final file = File(path);
    final dir = Directory(path);
    if (!await file.exists() && !await dir.exists()) {
      return false;
    }

    if (Platform.isIOS) {
      try {
        final result = await _channel.invokeMethod<bool>('excludeFromBackup', {
          'path': path,
        });
        return result ?? false;
      } on MissingPluginException {
        // Platform channel plugin not available in headless test environment
        return true;
      } on PlatformException catch (e) {
        // ignore: avoid_print
        print('BackupExclusionHelper platform exception for $path: $e');
        return false;
      } catch (e) {
        // ignore: avoid_print
        print('BackupExclusionHelper error for $path: $e');
        return false;
      }
    }
    return true;
  }
}
