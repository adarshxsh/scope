import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service responsible for managing the hardware-anchored 256-bit database encryption key.
class SecureKeyService {
  static const String defaultKeyName = 'attention_db_passphrase';

  final FlutterSecureStorage _storage;

  SecureKeyService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  /// Retrieves the existing 256-bit database passphrase or generates and stores a new one.
  Future<String> getOrCreatePassphrase({String keyName = defaultKeyName}) async {
    try {
      final existingKey = await _storage.read(key: keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (e) {
      debugPrint('Error reading secure key: $e');
    }

    final newKey = generate256BitPassphrase();
    try {
      await _storage.write(key: keyName, value: newKey);
    } catch (e) {
      debugPrint('Error writing secure key: $e');
    }
    return newKey;
  }

  /// Generates a cryptographically secure 256-bit passphrase (64 hex characters).
  static String generate256BitPassphrase() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
