import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SecureKeyService manages generating, storing, and retrieving the 256-bit
/// database encryption passphrase stored in hardware Keystore/Keychain.
class SecureKeyService {
  static const String _keyName = 'attention_os_db_key';
  final FlutterSecureStorage _storage;
  String? _cachedKey;

  SecureKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves the existing 256-bit key from secure storage, or generates and
  /// stores a new key if none exists.
  Future<String> getOrCreateDatabaseKey() async {
    if (_cachedKey != null) {
      return _cachedKey!;
    }

    try {
      final existingKey = await _storage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        _cachedKey = existingKey;
        return existingKey;
      }
    } catch (_) {
      // Secure storage may throw in headless or unit test environments
    }

    final newKey = generateRandom256BitKey();
    _cachedKey = newKey;

    try {
      await _storage.write(key: _keyName, value: newKey);
    } catch (_) {
      // Secure storage write unavailable in non-mobile test environments; cached in memory
    }

    return newKey;
  }

  /// Generates a random 256-bit (32-byte) hex string (64 characters).
  static String generateRandom256BitKey() {
    final random = Random.secure();
    final values = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      values[i] = random.nextInt(256);
    }
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Clears in-memory cached key for security / testing.
  void clearMemoryCache() {
    _cachedKey = null;
  }
}
