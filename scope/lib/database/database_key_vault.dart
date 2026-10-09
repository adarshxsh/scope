import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Vault responsible for securely generating, storing, and retrieving
/// the 256-bit database master passphrase backed by hardware key storage
/// (Android KeyStore / iOS Keychain).
class DatabaseKeyVault {
  static const String _defaultKeyName = 'attention_os_db_passphrase';

  final FlutterSecureStorage _storage;
  final String _keyName;

  DatabaseKeyVault({
    FlutterSecureStorage? storage,
    String keyName = _defaultKeyName,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _keyName = keyName;

  /// Retrieves existing passphrase from secure storage or generates a new
  /// cryptographically secure 256-bit (32-byte) key on first boot.
  Future<String> getOrCreatePassphrase() async {
    try {
      final existingKey = await _storage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {
      // Secure storage read error; fallback to generating a new key
    }
    return generateAndSaveNewPassphrase();
  }

  /// Generates a cryptographically secure 32-byte (256-bit) random key and persists it.
  Future<String> generateAndSaveNewPassphrase() async {
    final secureRandom = Random.secure();
    final randomBytes = List<int>.generate(32, (_) => secureRandom.nextInt(256));
    // Represent 32 bytes as a 64-character hexadecimal string
    final passphrase = randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    try {
      await _storage.write(key: _keyName, value: passphrase);
    } catch (_) {
      // Return generated passphrase even if secure storage write fails temporarily
    }
    return passphrase;
  }

  /// Clears the stored key (e.g., during wipe / test resets).
  Future<void> clearKey() async {
    try {
      await _storage.delete(key: _keyName);
    } catch (_) {}
  }
}
