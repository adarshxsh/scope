import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages generation, secure persistence, and retrieval of the 256-bit database encryption key.
class DatabaseKeyManager {
  static const String _keyStorageName = 'attention_os_db_encryption_key';
  final FlutterSecureStorage _storage;
  String? _cachedKey;

  DatabaseKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Retrieves the existing 256-bit encryption key or generates and stores a new one.
  ///
  /// Returns a 64-character hex string representing a 256-bit key.
  Future<String> getOrCreateKey() async {
    if (_cachedKey != null) {
      return _cachedKey!;
    }

    try {
      final storedKey = await _storage.read(key: _keyStorageName);
      if (storedKey != null && storedKey.isNotEmpty) {
        _cachedKey = storedKey;
        return storedKey;
      }
    } catch (_) {
      // Platform storage unavailable or mock fallback
    }

    final newKey = _generateSecureKeyHex();

    try {
      await _storage.write(key: _keyStorageName, value: newKey);
    } catch (_) {
      // Storage write fallback
    }

    _cachedKey = newKey;
    return newKey;
  }

  /// Sets the in-memory key (useful for tests).
  void setKeyForTesting(String key) {
    _cachedKey = key;
  }

  /// Generates 32 bytes (256 bits) of cryptographically secure random data
  /// formatted as a 64-character hexadecimal string.
  static String _generateSecureKeyHex() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
