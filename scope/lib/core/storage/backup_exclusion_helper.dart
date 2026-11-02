import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Helper to manage backup exclusions for application documents directory files on iOS.
class BackupExclusionHelper {
  static const MethodChannel _channel = MethodChannel('com.scope.backup');

  /// Applies backup exclusion rules on default sensitive files (`attention_os.db` and `rlhf_rules.json`).
  static Future<void> excludeSensitiveFiles() async {
    await excludeFromBackup('attention_os.db');
    await excludeFromBackup('rlhf_rules.json');
  }

  /// Sets the `NSURLIsExcludedFromBackupKey` attribute on iOS for a specified file name or path.
  static Future<bool> excludeFromBackup(String fileName, {String? filePath}) async {
    try {
      String resolvedPath = filePath ?? '';
      if (resolvedPath.isEmpty) {
        final dir = await getApplicationDocumentsDirectory();
        resolvedPath = p.join(dir.path, fileName);
      }

      final file = File(resolvedPath);
      if (!await file.exists()) {
        return false;
      }

      if (Platform.isIOS) {
        final result = await _channel.invokeMethod<bool>('excludeFromBackup', {
          'fileName': fileName,
          'filePath': file.path,
        });
        return result ?? false;
      }
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Fallback in test environment or non-iOS platforms
      return false;
    } catch (_) {
      return false;
    }
  }
}
