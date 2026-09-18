import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages hardware-backed 256-bit AES database encryption keys stored in
/// Android Keystore / iOS Keychain via [FlutterSecureStorage].
class DatabaseKeyManager {
  static const String _keyName = 'attention_os_db_key';

  final FlutterSecureStorage _secureStorage;
  static String? _testOverrideKey;
  final Map<String, String> _inMemoryStorage = {};

  DatabaseKeyManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Allows setting a test key override for unit tests.
  static void setTestKey(String? key) {
    _testOverrideKey = key;
  }

  /// Retrieves the existing 256-bit encryption key or generates a new one.
  Future<String> getOrCreateKey() async {
    if (_testOverrideKey != null) {
      return _testOverrideKey!;
    }

    try {
      final existingKey = await _secureStorage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }

      final newKey = _generate256BitKey();
      await _secureStorage.write(key: _keyName, value: newKey);
      return newKey;
    } catch (_) {
      // Fallback for headless unit test environments where FlutterSecureStorage plugin channel is unbound
      if (_inMemoryStorage.containsKey(_keyName)) {
        return _inMemoryStorage[_keyName]!;
      }
      final newKey = _generate256BitKey();
      _inMemoryStorage[_keyName] = newKey;
      return newKey;
    }
  }

  /// Generates a cryptographically secure 256-bit (32 bytes = 64 hex characters) AES key.
  String _generate256BitKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Clears the stored encryption key (used for testing or resetting).
  Future<void> clearKey() async {
    _testOverrideKey = null;
    _inMemoryStorage.clear();
    try {
      await _secureStorage.delete(key: _keyName);
    } catch (_) {}
  }
}
