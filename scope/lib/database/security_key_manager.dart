import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Handles platform hardware-backed key retrieval and secure local key storage fallback.
class SecurityKeyManager {
  static const MethodChannel _channel = MethodChannel('com.scope.keystore');
  static const String _keyFilename = '.attention_os.key';

  /// Retrieves or creates a 256-bit database encryption key.
  static Future<String> getDatabaseKey() async {
    try {
      final String? platformKey = await _channel.invokeMethod<String>('getDatabaseKey');
      if (platformKey != null && platformKey.isNotEmpty) {
        return platformKey;
      }
    } on MissingPluginException {
      // Platform channels unavailable (e.g. Linux desktop, integration tests)
    } on PlatformException {
      // Platform channel error
    } on UnsupportedError {
      // Background isolate or unsupported platform
    } catch (_) {
      // Other channel errors
    }

    // Secure local fallback for desktop/tests
    return await _getOrCreateLocalFallbackKey();
  }

  static Future<String> _getOrCreateLocalFallbackKey() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File keyFile = File(p.join(directory.path, _keyFilename));

    if (await keyFile.exists()) {
      final String key = (await keyFile.readAsString()).trim();
      if (key.length >= 32) {
        return key;
      }
    }

    final String newKey = _generateSecure256BitHexKey();
    await keyFile.writeAsString(newKey, flush: true);
    return newKey;
  }

  static String _generateSecure256BitHexKey() {
    final Random random = Random.secure();
    final List<int> values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
