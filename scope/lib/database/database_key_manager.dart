import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exception thrown when accessing platform secure storage for database encryption fails.
class SecureKeyStorageException implements Exception {
  final String message;
  final Object? cause;

  SecureKeyStorageException(this.message, [this.cause]);

  @override
  String toString() => 'SecureKeyStorageException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Abstract key storage interface to allow mocking or custom storage backends.
abstract class KeyStorage {
  Future<String?> readKey(String key);
  Future<void> writeKey(String key, String value);
  Future<void> deleteKey(String key);
}

/// Default implementation using FlutterSecureStorage.
class FlutterKeyStorage implements KeyStorage {
  final FlutterSecureStorage _storage;

  FlutterKeyStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  @override
  Future<String?> readKey(String key) async {
    return await _storage.read(key: key);
  }

  @override
  Future<void> writeKey(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> deleteKey(String key) async {
    await _storage.delete(key: key);
  }
}

/// In-memory key storage implementation for unit tests or environments without native keystore.
class InMemoryKeyStorage implements KeyStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> readKey(String key) async => _map[key];

  @override
  Future<void> writeKey(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    _map.remove(key);
  }
}

/// Manages database encryption master keys in platform hardware secure storage.
class DatabaseKeyManager {
  static const String defaultKeyName = 'attention_os_db_encryption_key';

  final KeyStorage _storage;
  final String _keyName;

  DatabaseKeyManager({KeyStorage? storage, String keyName = defaultKeyName})
      : _storage = storage ?? FlutterKeyStorage(),
        _keyName = keyName;

  /// Retrieves the existing 256-bit encryption key or generates and stores a new key.
  Future<String> getOrCreateKey() async {
    try {
      String? key = await _storage.readKey(_keyName);
      if (key == null || key.isEmpty) {
        key = generate256BitKey();
        await _storage.writeKey(_keyName, key);
      }
      return key;
    } catch (e) {
      throw SecureKeyStorageException(
        'Platform secure storage is inaccessible or failed to retrieve database key.',
        e,
      );
    }
  }

  /// Generates a cryptographically random 256-bit key (64 hex characters).
  static String generate256BitKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Clears stored key material from secure storage.
  Future<void> deleteKey() async {
    try {
      await _storage.deleteKey(_keyName);
    } catch (e) {
      throw SecureKeyStorageException('Failed to delete key from secure storage.', e);
    }
  }
}
