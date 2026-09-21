import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages hardware-backed secure key storage for SQLCipher database encryption.
class DatabaseKeyManager {
  static const String _keyStorageKey = 'attention_os_db_key';
  static String? _inMemoryFallbackKey;

  final FlutterSecureStorage _storage;

  DatabaseKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves the database encryption passphrase, generating a 256-bit key
  /// and storing it in hardware secure storage if it doesn't already exist.
  Future<String> getOrCreatePassphrase() async {
    try {
      final existingKey = await _storage.read(key: _keyStorageKey);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } on MissingPluginException catch (_) {
      if (_inMemoryFallbackKey != null) return _inMemoryFallbackKey!;
    } catch (_) {
      if (_inMemoryFallbackKey != null) return _inMemoryFallbackKey!;
    }

    final newKey = generateSecureKey();
    try {
      await _storage.write(key: _keyStorageKey, value: newKey);
    } on MissingPluginException catch (_) {
      _inMemoryFallbackKey = newKey;
    } catch (_) {
      _inMemoryFallbackKey = newKey;
    }
    return newKey;
  }

  /// Generates a cryptographically secure 256-bit key (64 hex characters).
  static String generateSecureKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Resets in-memory key (primarily for unit testing).
  static void resetInMemoryFallback() {
    _inMemoryFallbackKey = null;
  }
}
