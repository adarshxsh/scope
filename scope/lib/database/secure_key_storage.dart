import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Class managing in-memory sensitive passphrase material with byte-clearing capabilities.
class PassphraseHolder {
  List<int>? _bytes;

  PassphraseHolder(String passphrase) {
    _bytes = utf8.encode(passphrase);
  }

  /// Retrieves the passphrase string. Throws [StateError] if purged.
  String get passphrase {
    if (_bytes == null) {
      throw StateError('Passphrase has been purged from memory.');
    }
    return utf8.decode(_bytes!);
  }

  /// Zeroes out in-memory byte buffer and clears reference.
  void purge() {
    if (_bytes != null) {
      _bytes!.fillRange(0, _bytes!.length, 0);
      _bytes = null;
    }
  }
}

/// Helper service for managing local database passphrase in AndroidKeyStore / iOS Keychain.
class SecureKeyStorage {
  static const String _dbKeyName = 'attention_os_db_passphrase';

  final FlutterSecureStorage _storage;

  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Retrieves the database passphrase from hardware-backed secure storage.
  /// If no passphrase exists, generates a 256-bit passphrase via `Random.secure()` and saves it.
  Future<String> getOrCreateDatabasePassphrase() async {
    String? passphrase;

    try {
      passphrase = await _storage.read(key: _dbKeyName);
    } catch (_) {
      // Fallback gracefully to software KeyStore if EncryptedSharedPreferences / StrongBox fails
      try {
        const fallbackStorage = FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: false),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );
        passphrase = await fallbackStorage.read(key: _dbKeyName);
      } catch (_) {
        passphrase = null;
      }
    }

    if (passphrase != null && passphrase.isNotEmpty) {
      return passphrase;
    }

    // Generate new 256-bit passphrase
    final newPassphrase = generate256BitPassphrase();

    try {
      await _storage.write(key: _dbKeyName, value: newPassphrase);
    } catch (_) {
      // Fallback write if EncryptedSharedPreferences / StrongBox fails
      const fallbackStorage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: false),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
      await fallbackStorage.write(key: _dbKeyName, value: newPassphrase);
    }

    return newPassphrase;
  }

  /// Generates a cryptographically random 256-bit passphrase using [Random.secure()].
  static String generate256BitPassphrase() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
