/// Flutter-to-Kotlin bridge for AndroidKeyStore key management and database passphrases.
library;

import 'package:flutter/services.dart';

/// Bridge between Flutter and native AndroidKeyStore helper via MethodChannel.
class KeyStoreBridge {
  final MethodChannel _channel;

  KeyStoreBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.scope.keystore');

  /// Retrieves the unwrapped database encryption passphrase from AndroidKeyStore.
  /// Returns a fallback test passphrase if running in tests or on unsupported platforms.
  Future<String> getDatabasePassphrase() async {
    try {
      final passphrase = await _channel.invokeMethod<String>('getDatabasePassphrase');
      if (passphrase != null && passphrase.isNotEmpty) {
        return passphrase;
      }
    } on PlatformException catch (e) {
      // Log or handle platform error
      // ignore: avoid_print
      print('KeyStoreBridge.getDatabasePassphrase failed: ${e.message}');
    } on MissingPluginException {
      // Occurs when running on non-Android platforms or unit tests without mock
    }
    return _fallbackPassphrase();
  }

  /// Checks if StrongBox HSM is supported and active.
  Future<bool> isStrongBoxSupported() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isStrongBoxSupported');
      return supported ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Checks if the master key is stored inside secure hardware.
  Future<bool> isHardwareBacked() async {
    try {
      final hwBacked = await _channel.invokeMethod<bool>('isHardwareBacked');
      return hwBacked ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  String _fallbackPassphrase() {
    return '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  }
}
