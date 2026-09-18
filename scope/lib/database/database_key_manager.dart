import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages generation and secure platform storage of the SQLCipher database passphrase.
class DatabaseKeyManager {
  static const String _defaultKeyName = 'attention_os_db_passphrase';

  final FlutterSecureStorage _storage;
  final String _keyName;

  DatabaseKeyManager({
    FlutterSecureStorage? storage,
    String keyName = _defaultKeyName,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _keyName = keyName;

  /// Retrieves the 256-bit passphrase from secure storage, or generates and persists a new one.
  Future<String> getOrCreatePassphrase() async {
    try {
      final existingKey = await _storage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }

      final newKey = _generate256BitPassphrase();
      await _storage.write(key: _keyName, value: newKey);
      return newKey;
    } catch (_) {
      // Fallback for environments where platform secure storage plugin is unavailable
      return _generate256BitPassphrase();
    }
  }

  /// Generates a cryptographically secure 256-bit passphrase (64 hex characters).
  static String _generate256BitPassphrase() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
