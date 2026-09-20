import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Securely holds and purges passphrase byte material in memory.
class PassphraseHolder {
  Uint8List? _bytes;

  PassphraseHolder(String passphrase) {
    _bytes = Uint8List.fromList(utf8.encode(passphrase));
  }

  /// Returns the passphrase string if not purged.
  String get passphrase {
    final bytes = _bytes;
    if (bytes == null) {
      throw StateError('Passphrase material has been purged from memory.');
    }
    return utf8.decode(bytes);
  }

  /// Securely overwrites the byte buffer with zeros and clears memory references.
  void purge() {
    if (_bytes != null) {
      _bytes!.fillRange(0, _bytes!.length, 0);
      _bytes = null;
    }
  }

  /// Returns true if the passphrase material has been purged.
  bool get isPurged => _bytes == null;
}

/// Service for managing database passphrase generation and platform secure storage.
class SecureKeyStorage {
  static const String _keyName = 'attention_os_db_passphrase';
  final FlutterSecureStorage _storage;

  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Retrieves an existing 256-bit passphrase from platform secure storage,
  /// or generates a cryptographically strong 256-bit random passphrase upon first launch.
  Future<String> getOrCreatePassphrase() async {
    try {
      final existingKey = await _storage.read(key: _keyName);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {
      // Platform storage read failure fallback
    }

    final newPassphrase = generate256BitPassphrase();
    try {
      await _storage.write(key: _keyName, value: newPassphrase);
    } catch (_) {
      // Platform storage write failure fallback
    }
    return newPassphrase;
  }

  /// Generates a cryptographically strong 256-bit passphrase (32 random bytes as hex string).
  static String generate256BitPassphrase() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Deletes stored database passphrase (used in testing or resets).
  Future<void> deletePassphrase() async {
    try {
      await _storage.delete(key: _keyName);
    } catch (_) {}
  }
}
