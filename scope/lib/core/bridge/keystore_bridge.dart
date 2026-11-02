import 'package:flutter/services.dart';

/// Bridge to native AndroidKeyStore for retrieving hardware-backed database passphrase.
class KeyStoreBridge {
  static const MethodChannel _channel = MethodChannel('com.scope.keystore');

  /// Asynchronously requests the hardware-backed database passphrase from native AndroidKeyStore.
  /// Returns null if native channel is unavailable or returns an error.
  static Future<String?> getOrCreateDatabasePassphrase() async {
    try {
      final String? passphrase = await _channel.invokeMethod<String>('getOrCreateDatabasePassphrase');
      return passphrase;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
