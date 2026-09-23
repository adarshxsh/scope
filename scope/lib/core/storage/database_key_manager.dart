import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages retrieval and creation of the 256-bit SQLCipher database encryption key
/// stored in platform secure storage (Android Keystore / iOS Keychain).
class DatabaseKeyManager {
  static const String _keyAlias = 'db_encryption_key';
  final FlutterSecureStorage _secureStorage;
  static String? _inMemoryFallbackKey;

  DatabaseKeyManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Obtains the existing 256-bit passphrase key or generates a new one.
  Future<String> getOrCreateKey() async {
    if (Platform.environment.containsKey('FLUTTER_TEST') && _inMemoryFallbackKey != null) {
      return _inMemoryFallbackKey!;
    }

    try {
      final existingKey = await _secureStorage.read(key: _keyAlias);
      if (existingKey != null && existingKey.length >= 32) {
        return existingKey;
      }
    } catch (e) {
      debugPrint('DatabaseKeyManager: Secure storage read failed: $e');
      if (_inMemoryFallbackKey != null) {
        return _inMemoryFallbackKey!;
      }
    }

    final newKey = generate256BitKey();

    try {
      await _secureStorage.write(key: _keyAlias, value: newKey);
    } catch (e) {
      debugPrint('DatabaseKeyManager: Secure storage write failed: $e');
      _inMemoryFallbackKey = newKey;
    }

    return newKey;
  }

  /// Cryptographically generates a 256-bit (32-byte) key formatted as a 64-character hex string.
  static String generate256BitKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Resets in-memory key state (primarily for unit testing).
  @visibleForTesting
  static void resetState() {
    _inMemoryFallbackKey = null;
  }
}
