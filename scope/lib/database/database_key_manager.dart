import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages generation and secure retrieval of the 256-bit AES encryption key
/// for the SQLite database using OS secure key storage (Android KeyStore / iOS Keychain).
class DatabaseKeyManager {
  static const String _storageKey = 'attention_db_encryption_key';
  final FlutterSecureStorage _secureStorage;

  DatabaseKeyManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Retrieves the existing 256-bit encryption key or generates and stores a new one.
  Future<String> getOrCreateKey() async {
    try {
      final existingKey = await _secureStorage.read(key: _storageKey);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {
      // Fallback for storage read errors
    }

    final newKey = generate256BitKey();
    try {
      await _secureStorage.write(key: _storageKey, value: newKey);
    } catch (_) {
      // Fallback if write fails
    }
    return newKey;
  }

  /// Generates a 256-bit (32 bytes) cryptographically secure random key formatted as a 64-character hex string.
  static String generate256BitKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
