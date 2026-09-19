import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provider for managing the 256-bit database encryption passphrase
/// in platform hardware KeyStore / Keychain via [FlutterSecureStorage].
class DatabaseKeyProvider {
  static const String _defaultStorageKey = 'attention_os_db_passphrase';

  final FlutterSecureStorage _storage;
  final String _storageKey;

  DatabaseKeyProvider({
    FlutterSecureStorage? storage,
    String storageKey = _defaultStorageKey,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _storageKey = storageKey;

  /// Retrieves the existing 256-bit passphrase or generates a new cryptographically
  /// secure 256-bit passphrase using [Random.secure] if none exists.
  ///
  /// Throws [StateError] if secure storage operations fail.
  Future<String> getPassphrase() async {
    try {
      String? key = await _storage.read(key: _storageKey);
      if (key != null && key.isNotEmpty) {
        return key;
      }

      final newKey = _generateSecurePassphrase();
      await _storage.write(key: _storageKey, value: newKey);
      return newKey;
    } catch (e) {
      throw StateError('Failed to access secure key storage: $e');
    }
  }

  /// Generates a cryptographically secure 256-bit (32-byte) hex-encoded string.
  static String _generateSecurePassphrase() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
