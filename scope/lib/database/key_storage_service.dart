import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service responsible for securely generating, storing, and retrieving
/// the 256-bit encryption key for the SQLCipher database.
class KeyStorageService {
  static const String _keyName = 'scope_db_encryption_key_v1';
  final FlutterSecureStorage _secureStorage;
  String? _inMemoryKey;

  KeyStorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Gets the existing 256-bit database encryption key, or generates a new one
  /// if none exists.
  Future<String> getOrCreateEncryptionKey() async {
    // Fallback in-memory operation for automated tests or environments without keychain
    if (_isTestEnvironment()) {
      _inMemoryKey ??= _generate256BitKey();
      return _inMemoryKey!;
    }

    try {
      String? existingKey = await _secureStorage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }

      final newKey = _generate256BitKey();
      await _secureStorage.write(key: _keyName, value: newKey);
      return newKey;
    } catch (_) {
      // Fallback to in-memory key if hardware keychain is unavailable/throws
      _inMemoryKey ??= _generate256BitKey();
      return _inMemoryKey!;
    }
  }

  /// Generates a cryptographically strong 256-bit (32 bytes) hex-encoded key.
  String _generate256BitKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool _isTestEnvironment() {
    return Platform.environment.containsKey('FLUTTER_TEST');
  }
}
