import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages database encryption passphrases stored securely in platform hardware key stores
/// (Android Keystore / iOS Keychain via FlutterSecureStorage).
class SecureKeyStorage {
  static const String _keyName = 'attention_os_db_passphrase_v1';
  final FlutterSecureStorage _storage;
  String? _cachedPassphrase;

  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves or generates a 256-bit (32-byte hex-encoded) database encryption passphrase.
  /// Secure hardware storage is queried on first call and cached in memory.
  Future<String> getOrCreatePassphrase() async {
    if (_cachedPassphrase != null && _cachedPassphrase!.isNotEmpty) {
      return _cachedPassphrase!;
    }

    try {
      String? passphrase = await _storage.read(key: _keyName);
      if (passphrase == null || passphrase.isEmpty) {
        passphrase = _generate256BitPassphrase();
        await _storage.write(key: _keyName, value: passphrase);
      }
      _cachedPassphrase = passphrase;
      return passphrase;
    } catch (_) {
      // Fallback for environments where FlutterSecureStorage platform channel is unavailable
      // (e.g. headless unit tests without platform plugin mocks)
      if (_cachedPassphrase != null && _cachedPassphrase!.isNotEmpty) {
        return _cachedPassphrase!;
      }
      _cachedPassphrase = _generate256BitPassphrase();
      return _cachedPassphrase!;
    }
  }

  /// Generates a cryptographically secure 256-bit (32 random bytes) hex string.
  static String _generate256BitPassphrase() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Utility for testing environments to override or reset passphrase state.
  void setPassphraseForTesting(String? passphrase) {
    _cachedPassphrase = passphrase;
  }

  /// Utility for testing environments to clear cached passphrase.
  void clearCacheForTesting() {
    _cachedPassphrase = null;
  }
}
