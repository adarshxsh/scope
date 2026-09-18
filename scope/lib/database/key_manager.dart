import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages database encryption keys backed by OS hardware secure storage (KeyStore / Keychain).
class DatabaseKeyManager {
  static const String storageKey = 'db_encryption_key';
  final FlutterSecureStorage _storage;
  final Map<String, String>? _inMemoryFallback;

  DatabaseKeyManager({
    FlutterSecureStorage? storage,
    Map<String, String>? inMemoryFallback,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _inMemoryFallback = inMemoryFallback;

  /// Retrieves the existing 256-bit passphrase or generates a new one.
  Future<String> getOrCreateKey() async {
    final fallback = _inMemoryFallback;
    // Check in-memory fallback first if set
    if (fallback != null && fallback.containsKey(storageKey)) {
      return fallback[storageKey]!;
    }

    try {
      final existingKey = await _storage.read(key: storageKey);
      if (existingKey != null && existingKey.isNotEmpty) {
        if (fallback != null) {
          fallback[storageKey] = existingKey;
        }
        return existingKey;
      }
    } catch (e) {
      // Platform channel or headless test environment fallback
      if (fallback != null && fallback.containsKey(storageKey)) {
        return fallback[storageKey]!;
      }
    }

    // Generate new 256-bit passphrase (32 secure random bytes = 64 hex characters)
    final newKey = generateSecure256BitKey();

    try {
      await _storage.write(key: storageKey, value: newKey);
    } catch (e) {
      // Ignore secure storage errors in fallback test environment
    }

    if (fallback != null) {
      fallback[storageKey] = newKey;
    }

    return newKey;
  }

  /// Generates a cryptographically strong 256-bit passphrase (64 hex characters).
  static String generateSecure256BitKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
