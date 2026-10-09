import 'dart:io';
import 'package:flutter/services.dart';

/// Helper service for excluding files/directories from platform backup (e.g. iOS iCloud/iTunes backup).
class BackupExclusionService {
  static const MethodChannel _channel = MethodChannel('com.scope.attentions/backup_exclusion');

  /// Applies backup exclusion flag to the file or directory at [path].
  /// Returns `true` if successful or skipped (non-iOS platform), `false` if operation failed.
  static Future<bool> excludeFromBackup(String path) async {
    if (!Platform.isIOS) {
      return true;
    }

    try {
      final bool? result = await _channel.invokeMethod<bool>('excludeFromBackup', {'path': path});
      return result ?? true;
    } on MissingPluginException {
      // Gracefully ignore missing plugin in test runner or unsupported runtime
      return true;
    } on PlatformException catch (e) {
      // Log platform exception without crashing
      // ignore: avoid_print
      print('Failed to apply backup exclusion for path $path: ${e.message}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('Unexpected error applying backup exclusion for path $path: $e');
      return false;
    }
  }
}
