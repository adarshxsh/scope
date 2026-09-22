import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exception thrown when database key retrieval or generation fails.
class DatabaseKeyException implements Exception {
  final String message;
  final Object? cause;

  DatabaseKeyException(this.message, [this.cause]);

  @override
  String toString() => 'DatabaseKeyException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Abstract interface for secure storage access, enabling easy mocking in tests.
abstract class SecureStorageWrapper {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
}

/// Production implementation using FlutterSecureStorage.
class DefaultSecureStorageWrapper implements SecureStorageWrapper {
  final FlutterSecureStorage _storage;

  DefaultSecureStorageWrapper([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Manages retrieval and generation of the 256-bit SQLCipher database encryption key
/// stored in platform secure storage (Android Keystore / iOS Keychain).
class DatabaseKeyManager {
  static const String _dbKeyAlias = 'attention_os_db_key';
  final SecureStorageWrapper _secureStorage;

  DatabaseKeyManager([SecureStorageWrapper? secureStorage])
      : _secureStorage = secureStorage ?? DefaultSecureStorageWrapper();

  /// Retrieves the existing 256-bit passphrase from platform secure storage,
  /// or generates a new cryptographically secure 256-bit passphrase if none exists.
  ///
  /// Throws [DatabaseKeyException] if platform secure storage access fails.
  Future<String> getOrCreateKey() async {
    try {
      final existingKey = await _secureStorage.read(key: _dbKeyAlias);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }

      final newKey = _generate256BitKey();
      await _secureStorage.write(key: _dbKeyAlias, value: newKey);

      // Verify that the key was successfully written to secure storage
      final verifiedKey = await _secureStorage.read(key: _dbKeyAlias);
      if (verifiedKey != newKey) {
        throw DatabaseKeyException('Failed to verify newly generated database key in secure storage.');
      }

      return newKey;
    } catch (e) {
      if (e is DatabaseKeyException) rethrow;
      throw DatabaseKeyException(
        'Failed to retrieve or generate database encryption key from secure storage.',
        e,
      );
    }
  }

  /// Clears the stored database encryption key from platform secure storage.
  Future<void> clearKey() async {
    try {
      await _secureStorage.delete(key: _dbKeyAlias);
    } catch (e) {
      throw DatabaseKeyException('Failed to clear database key from secure storage.', e);
    }
  }

  /// Generates a cryptographically secure 256-bit (32 byte) key as a 64-character hex string.
  static String _generate256BitKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
