import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the generation, persistence, and retrieval of the 256-bit
/// SQLCipher database encryption key backed by platform hardware KeyStore / Keychain.
class DatabaseKeyManager {
  static const String _keyAlias = 'scope_db_encryption_key';
  final FlutterSecureStorage _secureStorage;
  final String? _testKey;

  DatabaseKeyManager({
    FlutterSecureStorage? secureStorage,
    String? testKey,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _testKey = testKey;

  /// Retrieves the existing 256-bit encryption key or generates a new one.
  Future<String> getOrCreateKey() async {
    final testKey = _testKey;
    if (testKey != null) {
      return testKey;
    }

    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');

    try {
      final existingKey = await _secureStorage.read(key: _keyAlias);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }

      final newKey = _generate256BitKey();
      await _secureStorage.write(key: _keyAlias, value: newKey);
      return newKey;
    } catch (e) {
      if (isTestEnv) {
        // Isolated test fallback key when platform secure storage channel is not available
        return '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      }
      rethrow;
    }
  }

  /// Generates 32 cryptographically secure random bytes (256 bits) as a 64-char hex string.
  String _generate256BitKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
