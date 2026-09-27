import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory holder for passphrase material supporting zeroing memory on purge.
class PassphraseHolder {
  Uint8List? _bytes;

  PassphraseHolder(Uint8List bytes) : _bytes = Uint8List.fromList(bytes);

  Uint8List? get bytes => _bytes;

  String? get asString => _bytes != null ? utf8.decode(_bytes!) : null;

  void purge() {
    if (_bytes != null) {
      _bytes!.fillRange(0, _bytes!.length, 0);
      _bytes = null;
    }
  }
}

/// Service managing secure database key generation and retrieval in Keychain / Keystore.
class DatabaseKeyService {
  final FlutterSecureStorage _storage;
  static const String defaultKeyName = 'attention_os_db_passphrase';

  DatabaseKeyService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves the existing database passphrase from secure storage, or generates
  /// and stores a new 256-bit cryptographically secure passphrase if none exists.
  Future<String> getOrGeneratePassphrase({String keyName = defaultKeyName}) async {
    try {
      final existingKey = await _storage.read(key: keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {
      // Platform storage error fallback
    }

    final newPassphrase = generateSecurePassphrase();
    try {
      await _storage.write(key: keyName, value: newPassphrase);
    } catch (_) {
      // Ignore secure storage write failures in restricted environments
    }
    return newPassphrase;
  }

  /// Generates a 256-bit (32-byte) cryptographically secure random hex string.
  static String generateSecurePassphrase() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Clears the stored database key from secure storage.
  Future<void> clearPassphrase({String keyName = defaultKeyName}) async {
    try {
      await _storage.delete(key: keyName);
    } catch (_) {}
  }
}
