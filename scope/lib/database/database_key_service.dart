import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages retrieval and generation of the cryptographically secure 256-bit
/// database encryption key using platform secure storage (Keychain / Keystore).
class DatabaseKeyService {
  static const String _keyName = 'attention_os_db_encryption_key';
  final FlutterSecureStorage _storage;

  DatabaseKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves the existing 256-bit encryption key or generates and stores a new one.
  Future<String> getOrCreateKey() async {
    try {
      final existingKey = await _storage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {
      // Handled if secure storage platform lookup is unavailable
    }

    final newKey = generateSecureKey();
    try {
      await _storage.write(
        key: _keyName,
        value: newKey,
        aOptions: const AndroidOptions(resetOnError: true),
      );
    } catch (_) {
      // Secure storage write error fallback
    }

    return newKey;
  }

  /// Generates a cryptographically secure 256-bit (32 bytes / 64 hex characters) key.
  static String generateSecureKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
