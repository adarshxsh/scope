import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Custom exception thrown when access to the platform secure key storage fails.
class DatabaseKeyException implements Exception {
  final String message;
  final dynamic cause;

  DatabaseKeyException(this.message, [this.cause]);

  @override
  String toString() =>
      'DatabaseKeyException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}

/// Abstract storage interface for storing database passphrase keys.
abstract class KeyStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Implementation using [FlutterSecureStorage] for KeyStore / Keychain integration.
class FlutterKeyStorageBackend implements KeyStorageBackend {
  final FlutterSecureStorage _storage;

  FlutterKeyStorageBackend([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}

/// In-memory storage backend for testing and platforms without native KeyStore/Keychain.
class InMemoryKeyStorageBackend implements KeyStorageBackend {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

/// Manages generation and secure storage of the 256-bit database encryption passphrase key.
class DatabaseKeyManager {
  static const String _keyAlias = 'attention_os_db_passphrase_key';
  final KeyStorageBackend _storageBackend;
  final Random _random;

  DatabaseKeyManager({
    KeyStorageBackend? storageBackend,
    Random? random,
  })  : _storageBackend = storageBackend ?? FlutterKeyStorageBackend(),
        _random = random ?? Random.secure();

  /// Retrieves the existing 256-bit passphrase key or generates and stores a new key.
  ///
  /// Throws [DatabaseKeyException] if platform secure storage fails to read or write.
  Future<String> getOrCreatePassphrase() async {
    try {
      final existingKey = await _storageBackend.read(_keyAlias);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }

      final newKey = generate256BitKey();
      await _storageBackend.write(_keyAlias, newKey);
      return newKey;
    } on PlatformException catch (e) {
      throw DatabaseKeyException(
        'Failed to access platform secure storage for database passphrase key',
        e,
      );
    } catch (e) {
      if (e is DatabaseKeyException) rethrow;
      throw DatabaseKeyException(
        'Unexpected error accessing database key in secure storage',
        e,
      );
    }
  }

  /// Generates a 256-bit (32 bytes = 64 hex characters) cryptographically secure random key.
  String generate256BitKey() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Clears the stored key (e.g. for testing or reset scenarios).
  Future<void> clearKey() async {
    try {
      await _storageBackend.delete(_keyAlias);
    } catch (e) {
      throw DatabaseKeyException('Failed to clear database key', e);
    }
  }
}
