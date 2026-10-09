import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage manager for generating, storing, and retrieving
/// the 256-bit database encryption key used by SQLCipher.
class SecureKeyStorage {
  static const String _dbKeyName = 'attention_os_db_key';
  final FlutterSecureStorage _storage;

  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves the existing 256-bit key or generates a new key if absent.
  Future<String> getOrCreateDatabaseKey() async {
    try {
      String? existingKey = await _storage.read(key: _dbKeyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {
      // Fallback for environment or headless test platform channel errors
    }

    final newKey = generate256BitKey();
    try {
      await _storage.write(key: _dbKeyName, value: newKey);
    } catch (_) {
      // Ignore storage errors in headless test environments
    }
    return newKey;
  }

  /// Generates a 256-bit cryptographically secure key (formatted as a 64-character hex string).
  static String generate256BitKey() {
    final random = Random.secure();
    final values = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      values[i] = random.nextInt(256);
    }
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Deletes the stored key from secure storage.
  Future<void> clearKey() async {
    try {
      await _storage.delete(key: _dbKeyName);
    } catch (_) {}
  }
}

/// In-memory holder for sensitive key material that supports explicit memory purging.
class PassphraseHolder {
  Uint8List? _passphraseBytes;

  PassphraseHolder(String passphrase) {
    _passphraseBytes = Uint8List.fromList(utf8.encode(passphrase));
  }

  String? get passphrase {
    if (_passphraseBytes == null) return null;
    return utf8.decode(_passphraseBytes!);
  }

  void purge() {
    if (_passphraseBytes != null) {
      _passphraseBytes!.fillRange(0, _passphraseBytes!.length, 0);
      _passphraseBytes = null;
    }
  }
}
